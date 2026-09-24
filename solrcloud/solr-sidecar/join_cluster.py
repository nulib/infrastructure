"""Sidecar for the solr task: add a replica of every collection to this node, then exit.

Runs as a non-essential container next to Solr. Once this node holds an active replica
of every replicable shard, and each of those shards has a live leader, it writes
MARKER_FILE to a volume shared with the solr container, whose health check won't report
ready until that file exists. Exits non-zero without writing the marker on failure, which
keeps the task from ever becoming healthy. See DEPLOYMENT_UPDATE.md.

A shard is replicable when some other live node holds a replica of it, in any state. A
shard with none (every replica is on a dead node, e.g. after losing the whole cluster) has
no data to copy or protect, so it is skipped -- but only once that has held for
STABILITY_WINDOW seconds, so a brief ZooKeeper session drop on the nodes that do hold the
data can't make them look dead.

The health check also asks Solr for requireHealthyCores, but Solr only treats DOWN and
RECOVERING as unhealthy there -- a RECOVERY_FAILED replica passes. That's why this script
waits for `active` itself instead of stopping once ADDREPLICA succeeds.

Standard library only, so it runs on a stock python image.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SOLR_URL = os.environ.get("SOLR_URL", "http://localhost:8983/solr")
MARKER_FILE = os.environ.get("MARKER_FILE", "/gate/replicas-active")
JOIN_TIMEOUT = int(os.environ.get("JOIN_TIMEOUT", "240"))
# Just under the solr health check budget (startPeriod 300 + 3 x 30s), so a stuck
# recovery is logged here before ECS kills the task
ACTIVE_TIMEOUT = int(os.environ.get("ACTIVE_TIMEOUT", "330"))
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "5"))
STABILITY_WINDOW = int(os.environ.get("STABILITY_WINDOW", "120"))


def log(message):
    print(f"[join-cluster] {message}", flush=True)


def solr_get(path, timeout=120, **params):
    query = urllib.parse.urlencode({**params, "wt": "json"})
    with urllib.request.urlopen(f"{SOLR_URL}{path}?{query}", timeout=timeout) as response:
        return json.load(response)


def cluster_status():
    return solr_get("/admin/collections", action="CLUSTERSTATUS")["cluster"]


def wait_for_node():
    """Return this node's Solr node name once it appears in live_nodes."""
    deadline = time.monotonic() + JOIN_TIMEOUT
    while time.monotonic() < deadline:
        try:
            node = solr_get("/admin/info/system", timeout=10).get("node")
            if node and node in cluster_status()["live_nodes"]:
                return node
        except (urllib.error.URLError, OSError, ValueError, KeyError):
            pass  # Solr not up or not connected to ZooKeeper yet
        time.sleep(5)
    raise TimeoutError(f"node did not join the cluster within {JOIN_TIMEOUT}s")


def active_shards(cluster):
    for collection, state in sorted(cluster.get("collections", {}).items()):
        for shard, shard_state in sorted(state.get("shards", {}).items()):
            if shard_state.get("state", "active") == "active":  # skips e.g. split parents
                yield collection, shard, shard_state.get("replicas", {}).values()


def unreplicable_shards(cluster, node):
    """Return the set of (collection, shard) with no replica on any other live node."""
    live = set(cluster.get("live_nodes", [])) - {node}
    return {
        (collection, shard)
        for collection, shard, replicas in active_shards(cluster)
        if not any(r.get("node_name") in live for r in replicas)
    }


def find_unreplicable(node):
    """Return shards that stayed unreplicable for the whole STABILITY_WINDOW.

    Returns at once when every shard is replicable (the normal case). A shard that is
    replicable in any poll during the window is treated as replicable.
    """
    candidates = unreplicable_shards(cluster_status(), node)
    if not candidates:
        return set()
    log(f"no other live node holds {fmt(candidates)}; rechecking for {STABILITY_WINDOW}s")
    deadline = time.monotonic() + STABILITY_WINDOW
    while candidates and time.monotonic() < deadline:
        time.sleep(POLL_INTERVAL)
        try:
            candidates &= unreplicable_shards(cluster_status(), node)
        except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
            log(f"CLUSTERSTATUS failed while rechecking: {error}")
    return candidates


def fmt(shards):
    return " ".join(f"{c}/{s}" for c, s in sorted(shards))


def missing_shards(cluster, node, skip=()):
    """Yield (collection, shard) for every active shard with no usable replica on node.

    A `down` replica on this node doesn't count: Fargate can reuse a stopped task's IP,
    leaving a stale replica under our node name with no core behind it.
    """
    for collection, shard, replicas in active_shards(cluster):
        if (collection, shard) in skip:
            continue
        if not any(r.get("node_name") == node and r.get("state") != "down" for r in replicas):
            yield collection, shard


def replication_status(cluster, node, skip=()):
    """Return ("active" | "waiting" | "failed", detail) for this node's replicas.

    Active means every active shard not in `skip` has an `active` replica on this node and
    a leader on a live node. Any `recovery_failed` replica on this node is a failure; it
    won't recover.
    """
    live = set(cluster.get("live_nodes", []))
    waiting = []
    for collection, shard, replicas in active_shards(cluster):
        if (collection, shard) in skip:
            continue
        mine = [r for r in replicas if r.get("node_name") == node]
        if any(r.get("state") == "recovery_failed" for r in mine):
            return "failed", f"{collection}/{shard} replica on {node} is recovery_failed"
        has_leader = any(r.get("leader") == "true" and r.get("node_name") in live for r in replicas)
        if not has_leader or not any(r.get("state") == "active" for r in mine):
            states = ",".join(r.get("state", "?") for r in mine) or "none"
            waiting.append(f"{collection}/{shard}={states}{'' if has_leader else ' (no live leader)'}")
    return ("waiting", " ".join(waiting)) if waiting else ("active", "")


def wait_for_active(node, skip=()):
    deadline = time.monotonic() + ACTIVE_TIMEOUT
    last = None
    while time.monotonic() < deadline:
        try:
            status, detail = replication_status(cluster_status(), node, skip)
        except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
            status, detail = "waiting", f"CLUSTERSTATUS failed: {error}"
        if status == "active":
            return
        if status == "failed":
            raise RuntimeError(detail)
        if detail != last:
            log(f"waiting: {detail}")
            last = detail
        time.sleep(POLL_INTERVAL)
    raise TimeoutError(f"replicas not active within {ACTIVE_TIMEOUT}s: {last}")


def add_replica(collection, shard, node, attempts=3):
    for attempt in range(1, attempts + 1):
        try:
            response = solr_get(
                "/admin/collections",
                action="ADDREPLICA",
                collection=collection,
                shard=shard,
                node=node,
                waitForFinalState="false",
            )
            if response.get("responseHeader", {}).get("status") == 0:
                log(f"added replica of {collection}/{shard}")
                return
            log(f"ADDREPLICA {collection}/{shard} attempt {attempt}: {json.dumps(response)}")
        except urllib.error.HTTPError as error:
            log(f"ADDREPLICA {collection}/{shard} attempt {attempt}: HTTP {error.code} {error.read()[:500]!r}")
        except (urllib.error.URLError, OSError) as error:
            log(f"ADDREPLICA {collection}/{shard} attempt {attempt}: {error}")
        time.sleep(10)
    raise RuntimeError(f"ADDREPLICA {collection}/{shard} failed after {attempts} attempts")


def main():
    node = wait_for_node()
    log(f"joined cluster as {node}")

    skip = find_unreplicable(node)
    if skip:
        log(f"WARNING: no live copy of {fmt(skip)} anywhere; skipping. Restore from backup.")

    todo = list(missing_shards(cluster_status(), node, skip))
    if not todo:
        log("every replicable shard already has a replica on this node")
    for collection, shard in todo:
        add_replica(collection, shard, node)

    wait_for_active(node, skip)
    log("every replicable shard has an active replica on this node")

    os.makedirs(os.path.dirname(MARKER_FILE), exist_ok=True)
    with open(MARKER_FILE, "w") as marker:
        marker.write(f"{node}\n")
    log(f"wrote {MARKER_FILE}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        log(f"FAILED: {error}")
        sys.exit(1)
