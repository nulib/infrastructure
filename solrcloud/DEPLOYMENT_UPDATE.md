# SolrCloud Replication-Aware Deployment Strategy

## Context / infrastructure

- SolrCloud cluster on **Fargate**: 3 ZooKeeper nodes and 3 Solr nodes (staging and
  production are the same size: 8 GB tasks, 4000m heap).
- 2 collections (`arch`, `avr`), 1 shard each, replicated across all 3 Solr nodes.
- ECS service deployment config: `minimumHealthyPercent: 100`, `maximumPercent: 200`.
  These are the AWS defaults, now written out explicitly in `solr.tf`.
- The utility Lambda (`backup-lambda/`, deployed as `<namespace>-solr-utils`) has
  `solr:rebalance`, `solr:status`, and `solr:prune-dead` operations. See
  [Lambda hazards](#lambda-hazards) for what was fixed.

## Incident that prompted this

All 3 Solr nodes stopped within the same deployment window on a Friday night, leaving no
active replica for any shard to recover from. We had to restore from backup.

**Diagnosis performed:**
- CloudWatch `MemoryUtilization`/`CPUUtilization` for the week around the incident:
  memory was declining into the crash (not spiking), and CPU dropped straight to near zero
  (not spiking then dropping). That **ruled out OOM or resource exhaustion**.
- CloudTrail: the only `StopTask` events were user- or deploy-initiated (not agent- or
  OOM-initiated). No `ECS Task State Change` events were available after the fact; those
  only exist if an EventBridge rule was capturing them live at the time, and none was.
- CloudWatch Logs retention was only 3 days, so the raw Solr and task logs were already
  gone. **Fixed:** retention is now 14 days (`main.tf`).

**Root cause:** `minimumHealthyPercent: 100%` / `maximumPercent: 200%` only protects
against dropping below the desired *task* count. It says nothing about whether the
*SolrCloud replicas* on the new tasks have synced. A task can pass ECS's container health
check (process up, port responsive) while its Solr replica is still empty or mid-recovery.
If a deploy or restart touches several nodes in turn without waiting for real
replication, a shard can end up with zero synced replicas even though ECS reports the
service as steady.

**Further leads found during the staging test (not yet checked against the incident):**
- ECS stops **every** task in a service at once, ignoring `minimumHealthyPercent`, when
  their Cloud Map registrations disappear (see [Staging test results](#staging-test-results)).
  If anything deregistered Solr's instances or deleted its Cloud Map service
  (`srv-nnjfewy4xwntmdp2` in staging) around the incident, this would explain it. These
  stops appear as `stopCode=ServiceSchedulerInitiated`, not as `StopTask` calls.

## Strategy: gate readiness in the container health check

ECS moves a deployment forward, and stops an old task, the moment a new task's
**container health check** passes. That is the only signal it waits on (see
[Why not Cloud Map custom health checks](#why-not-cloud-map-custom-health-checks)). So the
gate goes into the Solr container itself:

1. **A sidecar adds this node's replicas.** The Solr task keeps the stock `solr` image
   and gains a second, **non-essential** container, `join-cluster`. It runs the stock
   `python:3-slim` image with `solr-sidecar/join_cluster.py`, passed in through `command`,
   and starts after Solr (`dependsOn: solr START`). Containers in an `awsvpc` task share
   `localhost`. The script waits for local Solr to join the cluster (its node appears in
   `live_nodes`), then calls `ADDREPLICA node=<self>` for each shard that has no replica
   on this node. It then polls `CLUSTERSTATUS` until this node has an `active` replica of
   every shard and every shard has a leader on a live node. Then it writes
   `/gate/replicas-active` to a task volume shared with the Solr container and exits 0.
   On failure (a `recovery_failed` replica, a timeout, or `ADDREPLICA` errors) it exits 1
   with no marker. ECS only reads essential containers' health checks, so the sidecar can't gate
   anything by itself; its exit doesn't affect the task.
2. **Health check reports ready only once, then only checks liveness.** Until the node has
   first been ready, the Solr container's health check (an inline `CMD-SHELL` using the
   stock image's `wget`) passes only when:
   - the sidecar's marker file exists, and
   - `GET /solr/admin/info/health?requireHealthyCores=true` succeeds. That fails if Solr
     has lost its ZooKeeper connection, isn't in `live_nodes`, is still loading cores, or
     has a local core in an active shard that is `down` or `recovering`.

   `requireHealthyCores` alone isn't enough. In Solr's `HealthCheckHandler`,
   `UNHEALTHY_STATES` is only `DOWN` and `RECOVERING`, so a `recovery_failed` replica
   passes. That's why the sidecar waits for `active` itself.

   On that first pass it writes `/tmp/solr-ready` in the Solr container's own filesystem.
   (The Solr container mounts `/gate` read-only. The sidecar runs as root and does the
   only write, which avoids Fargate bind-mount permission problems for the `solr` user.)
   From then on it only checks liveness, as today (`/solr/` responds). This matters
   because ECS has no separate readiness check. If the replication requirement stayed in place, a replica briefly recovering
   during normal operation would get its node killed, which triggers more recovery.
3. **ECS does the rest.** Old tasks keep running until new tasks pass. A task that never
   becomes ready is killed once `startPeriod` plus `interval × retries` runs out, and the
   **deployment circuit breaker** rolls the deployment back after repeated failures.

This needs no custom image, EventBridge rule, Step Function, or Cloud Map change. Editing
`join_cluster.py` changes the task definition, so the change deploys on the next apply.

### Health check timing

Measured in staging 2026-09-24 (staging matches production size). The time runs from
`ADDREPLICA` to the new replica being `active`, with 5-second polling:

| Collection | Index size | Time to `active` |
| --- | --- | --- |
| `arch` | 2.3 GB | 26s |
| `avr` | 673 MB | 11s |

That's about 90 MB/s. On ECS, a health check that passes during `startPeriod` marks the
task healthy immediately, and failures during `startPeriod` don't count, so a long
`startPeriod` costs nothing on the normal path.

| Setting | Value | Why |
| --- | --- | --- |
| `startPeriod` | 300 | The ECS maximum. Covers JVM start, joining ZooKeeper, `ADDREPLICA`, and recovery. |
| `interval` | 30 | Same as today. |
| `retries` | 3 | Same as today, so a dead node is still detected in about 90s once ready. |
| `timeout` | 5 | Same as today. |

That gives a total budget of about 390s, roughly 15× the measured 26s. At 90 MB/s it
covers about 35 GB of index, which is more than each node's 20.5 GB disk can hold. The
measurement used idle leaders and a node that was already running; the margin is meant to
cover boot time and production query load.

### Details and edge cases

- **Node name.** Solr registers as `<task-private-ip>:8983_solr`. The sidecar reads it
  from Solr itself (`node` in `/solr/admin/info/system`), so it needs no ECS metadata.
- **Which collections.** Every active shard of every collection in `CLUSTERSTATUS`, so
  adding a collection needs no config change. Inactive shards, such as the parent of a
  completed split, are skipped. A shard that already has a replica on this node is
  skipped, so the script can safely run again.
- **Reused IPs.** Fargate can give a new task a stopped task's IP, leaving a `down`
  replica under this node's name with no core behind it. The sidecar ignores `down`
  replicas on its own node when deciding what's missing.
- **Concurrent new tasks.** At `maximumPercent: 200` ECS may start all 3 replacements at
  once, so each leader may serve 3 recoveries at the same time. Expected to be fine at
  these index sizes; confirm when testing in staging.
- **`down` replicas pile up.** Each stopped task leaves `down` replicas in cluster state
  for every collection. They don't block the health check, which only looks at local
  cores, but they need regular cleanup: a Lambda `solr:prune-dead` operation, run after
  deploys or on a schedule. The sidecar must **not** delete replicas itself.
- **`ADDREPLICA` fails.** The sidecar retries each call 3 times, 10s apart. If it still
  fails, no marker is written and the health check never passes. The task is killed at
  the end of its budget, and the circuit breaker takes over. The same happens if the node
  hasn't joined the cluster within 240s (`JOIN_TIMEOUT`), or its replicas aren't `active`
  within 330s (`ACTIVE_TIMEOUT`, just under the health check's 390s budget, so the reason
  is logged before ECS kills the task).
- **`recovery_failed`.** The sidecar exits 1 as soon as one of this node's replicas
  reaches it, since it won't recover on its own.
- **Live copy, no live leader.** The sidecar requires a leader on a live node for every
  replicable shard, so it waits (and eventually times out) rather than passing.
- **First rollout.** The gate lives in the new task definition, so the rollout that
  introduces it is already gated by it. Old tasks have no gate, but they are the ones
  being replaced.

## Disaster recovery: automatic, no bootstrap flag

An earlier version needed a `solr_bootstrap_mode` variable to bypass the gate when
restoring an empty cluster from backup. The sidecar now works that out itself:

- A shard is **replicable** when some *other* node in `live_nodes` holds a replica of it,
  in any state. `down` and `recovering` count too, so a whole-cluster restart (leaders
  still being elected) is treated as "data exists" and waited for.
- A shard with no replica on any other live node has no live copy anywhere, so there is
  nothing to copy and nothing to protect. The sidecar skips it and logs
  `WARNING: no live copy of ... anywhere`.
- It skips a shard only if that stays true for `STABILITY_WINDOW` (120s) of repeated
  checks. Otherwise a brief ZooKeeper session drop on the nodes that do hold the data
  would make them look dead, and ECS would stop them once the new node passed.
- The node becomes ready once every *replicable* shard has an `active` replica on it. A
  cluster with no collections, or with every replica on dead nodes, passes after the
  window, which is what bootstrap mode used to do.

This gives up the original rule that bootstrap must be "a deliberate human action". The
only case that bypasses the gate is one where no live node has the data, so there is
nothing for the gate to protect.

After a total loss, restore the collections by hand (`solr:restore`), then run
`solr:rebalance` with `expand: true` to backfill replicas.

## ZooKeeper: stock image, backup sidecar, sequential rollout

The custom `zk-image/` (stock entrypoint plus S3 restore and backup) is replaced by the
stock `zookeeper:3.9` image and a `zk-backup` sidecar on the stock `aws-cli` image.
Nothing is built or pushed any more, so the Docker provider and ECR login are gone from
`main.tf`. Each member is the `zookeeper-node/` module, instantiated three times in
`zookeeper.tf`.

### Per task

- **Shared volumes.** `/data` and `/datalog` are task volumes shared by both containers.
  The stock entrypoint starts as root and `chown`s them before dropping to the
  `zookeeper` user. A third volume, `/gate`, carries the sidecar's decisions.
- **`zk-backup` sidecar** (non-essential; `zookeeper-sidecar/backup.sh`, passed in through
  `command`):
  1. **Before ZooKeeper starts**, it probes the other members with `srvr`. If any reports
     `Mode: leader` or `follower`, a quorum is serving, so it starts empty and lets the
     leader sync it (mode `joined`). Otherwise it restores this node's S3 backup
     (`restored`), or starts a brand-new ensemble if there is none (`fresh`). It writes the
     mode to `/gate/mode`, then `/gate/ready`, which makes its own health check pass. The
     zookeeper container has `dependsOn: zk-backup HEALTHY`.
  2. Every 360s it forces a snapshot through the admin server (`127.0.0.1:8080`), then
     runs `aws s3 sync` on both directories. It skips this while the node isn't serving,
     so a node still syncing never uploads a partial copy over a good backup.
  3. On `SIGTERM` it takes a final backup. With `dependsOn`, ECS stops ZooKeeper first and
     the sidecar last, so this runs after ZooKeeper has shut down cleanly.

  The S3 layout (`s3://<bucket>/zk/<myid>/data/` and `datalog/`) is unchanged, so existing
  backups stay usable.
- **ZooKeeper health check** (`zookeeper-sidecar/healthcheck.sh`):
  - **Healthy** when this node is part of a serving quorum, or when no quorum exists
    anywhere. The second case is a whole-ensemble cold start: nothing can serve until 2
    of 3 are up, so requiring it would deadlock a sequential rollout.
  - **Unhealthy** when this node isn't serving but a peer is, meaning it's still syncing
    or has been refused.
- **Semaphore znode `/nul/ensemble-initialized`.** Once serving, the health check verifies
  it once (then writes `/tmp/zk-verified` and stops calling `zkCli`):
  - `restored` / `fresh` nodes create it if it's missing.
  - A `joined` node requires it. A live ensemble without it formed from empty nodes (a
    failed restore, for example), and joining it would bury this node's good S3 backup.
    Such a node stays unhealthy, which stops the rollout.

  Each `zkCli` run starts a JVM, so each check makes at most one call, with commands on
  stdin. That took about 1s locally; Fargate's quarter vCPU will be slower, so the check
  timeout is 20s.

### Rolling one member at a time

- **The problem.** With `count`, Terraform updated all three services in parallel and
  didn't wait for ECS, so ECS replaced all three members at once. With 100/200, each
  service briefly ran two servers with the same `myid`.
- **Now:** `module "zookeeper_2"` depends on `module "zookeeper_1"`, and `zookeeper_3` on
  `zookeeper_2`. Each ECS service has `wait_for_steady_state = true`, so Terraform waits
  for a member to be healthy (serving) before rolling the next.
- **0/100:** each service stops its old task before starting the new one, so a `myid`
  never has two servers. One member is briefly down while 2 of 3 keep quorum.
- **Circuit breaker** with rollback on each service. If a member never becomes healthy,
  the apply fails before touching the rest.
- **Solr waits for ZooKeeper:** `aws_ecs_service.solr` depends on `module.zookeeper_3`, so
  a combined apply rolls Solr only after the ensemble is steady.
- **Fixed size:** the ensemble size is fixed at 3 (`local.zookeeper_ensemble_size`); the
  `zookeeper_ensemble_size` variable is gone.
- **Existing pre-flight gap:** nothing checks that the *other* members are healthy before
  rolling one. If a member is already down, rolling a second loses quorum until the
  first comes back.
