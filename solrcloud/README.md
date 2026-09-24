## Description

This terraform project includes the resources required to get the Solrcloud (Solr / Zookeeper) cluster running.

## Prerequisites

* [core](../core/README.md)

## Secrets

* `state_bucket` - The bucket containing remote state files (default: `nulterra-state-sandbox`)
* `zookeeper.cpu` - The amount of CPU to reserve for each zookeeper instance (default: `256`)
* `zookeeper.memory` - The amount of RAM to reserve for each zookeeper instance (default: `512`)
* `solr.cluster_size` - The number of Solr nodes to run (default: `4`)
* `solr.cpu` - The amount of CPU to reserve for each solr instance (default: `1024`)
* `solr.memory` - The amount of RAM to reserve for each solr instance (default: `2048`)

## Deployments

A new Solr task only reports healthy, letting ECS stop an old one, once it hosts an
`active` replica of every collection. A non-essential `join-cluster` sidecar
(`solr-sidecar/join_cluster.py`) adds the replicas. The Solr container's health check
waits for them. See [DEPLOYMENT_UPDATE.md](DEPLOYMENT_UPDATE.md) for the design.

After a rollout, clear the old tasks' replicas with the utility Lambda's `solr:prune-dead`.

A shard with no copy on any other live node (after losing the whole cluster) is skipped
once that has held for 2 minutes. No flag is needed to restore an empty cluster: restore
the collections with `solr:restore`, then run `solr:rebalance` with `expand: true`.

### ZooKeeper

Each member runs the stock `zookeeper` image plus a `zk-backup` sidecar
(`zookeeper-sidecar/backup.sh`, on the stock `aws-cli` image). Before ZooKeeper starts,
the sidecar joins a serving ensemble if there is one, and otherwise restores this
member's S3 backup. After that it backs up every 6 minutes and on shutdown. Members are
the `zookeeper-node/` module, rolled one at a time: each waits for the previous one to be
healthy, meaning part of a serving quorum.

A member that joins a live ensemble requires the `/nul/ensemble-initialized` znode, which
restored or fresh members create. An ensemble without it formed from empty members, and
joining members stay unhealthy rather than vouch for it.

### Startup sequences

A full apply rolls ZooKeeper members 1, 2 and 3 one at a time, each waiting for the
previous one's deployment to be `SUCCESSFUL`, and then Solr.

#### ZooKeeper member

```mermaid
sequenceDiagram
    autonumber
    participant ECS
    participant B as zk-backup sidecar<br/>(aws-cli image)
    participant ZK as zookeeper container<br/>(stock image)
    participant P as Other ensemble members
    participant S3 as S3 backup bucket

    ECS->>B: Start task (old task already stopped, 0/100)
    Note over ZK: Not started yet:<br/>dependsOn zk-backup HEALTHY
    B->>P: srvr probe on port 2181, each other member
    alt A peer reports Mode leader or follower
        B->>B: mode = joined (start empty, leader will sync us)
    else No peer serving and S3 has a backup
        B->>S3: s3 sync zk/myid/data and datalog
        S3-->>B: Snapshots and logs into /data and /datalog
        Note over B: If the sync fails: exit 1 with no ready file,<br/>ZooKeeper never starts and ECS stops the task
        B->>B: mode = restored
    else No peer serving and no backup
        B->>B: mode = fresh (brand-new ensemble)
    end
    B->>B: Write /gate/mode, then /gate/ready
    ECS->>B: Sidecar health check: test -f /gate/ready
    B-->>ECS: HEALTHY
    ECS->>ZK: Start zookeeper
    ZK->>ZK: chown shared volumes, write myid, start server
    alt mode = joined
        ZK->>P: Join quorum, sync from leader (DIFF or SNAP)
    else mode = restored or fresh
        ZK->>P: Leader election, highest zxid wins
    end

    loop ZooKeeper health check every 15s (startPeriod 120s, 4 retries)
        ECS->>ZK: healthcheck.sh
        alt This member is serving (leader or follower)
            opt First time only (no /tmp/zk-verified)
                alt mode = joined
                    ZK->>ZK: zkCli stat /nul/ensemble-initialized
                    Note over ZK: Missing: UNHEALTHY, refuse to vouch<br/>for an ensemble that formed from empty members
                else mode = restored or fresh
                    ZK->>ZK: zkCli create /nul/ensemble-initialized if missing
                end
                ZK->>ZK: touch /tmp/zk-verified
            end
            ZK-->>ECS: HEALTHY
        else Not serving, but a peer is serving
            ZK-->>ECS: UNHEALTHY (still syncing, or refused)
        else Not serving, and no peer is serving
            ZK-->>ECS: HEALTHY (whole-ensemble cold start)
        end
    end
    Note over ECS: Deployment SUCCESSFUL.<br/>Terraform (wait_for_steady_state) rolls the next member,<br/>and Solr only after member 3

    loop Every 360s while running
        B->>ZK: srvr probe on localhost
        opt Serving (leader or follower)
            B->>ZK: Admin server snapshot (port 8080)
            B->>S3: s3 sync /data and /datalog
        end
    end
    Note over ECS,S3: On task stop
    ECS->>ZK: SIGTERM (stopped first, it depends on the sidecar)
    ECS->>B: SIGTERM
    B->>S3: Final backup (stopTimeout 60s)
```

#### Solr node

```mermaid
sequenceDiagram
    autonumber
    participant ECS
    participant Solr as solr container<br/>(stock image)
    participant J as join-cluster sidecar<br/>(python:3-slim)
    participant C as SolrCloud cluster<br/>(via local Collections API)

    Note over ECS: New tasks start alongside the old ones (100/200)
    ECS->>Solr: Start solr
    Solr->>C: Connect to ZooKeeper, register in live_nodes
    ECS->>J: Start join-cluster (dependsOn solr START)
    loop Every 5s, up to 240s (JOIN_TIMEOUT)
        J->>Solr: /admin/info/system for this node name
        J->>C: CLUSTERSTATUS: is this node in live_nodes?
    end
    Note over J: Not joined in time: exit 1 with no marker

    J->>C: CLUSTERSTATUS
    alt Every active shard has a replica on another live node
        Note over J: Normal case, no wait
    else Some shards have no replica on any other live node
        loop Recheck every 5s for 120s (STABILITY_WINDOW)
            J->>C: CLUSTERSTATUS
        end
        Note over J: A shard that reappears is replicated normally.<br/>One still missing everywhere is skipped:<br/>WARNING no live copy, restore from backup
    end

    loop Each replicable shard with no usable replica on this node
        Note over J: A down replica under this node name does not count<br/>(Fargate can reuse a stopped task's IP)
        J->>C: ADDREPLICA node=self (3 attempts, 10s apart)
    end
    Note over J: ADDREPLICA still failing: exit 1 with no marker

    loop Every 5s, up to 330s (ACTIVE_TIMEOUT)
        J->>C: CLUSTERSTATUS
        alt A replica on this node is recovery_failed
            J-->>ECS: exit 1 with no marker (it won't recover)
        else Still recovering, or a shard has no live leader
            Note over J: Keep waiting
        else Every replicable shard: active here with a live leader
            J->>J: Write /gate/replicas-active, exit 0
        end
    end

    loop Solr health check every 30s (startPeriod 300s, 3 retries)
        ECS->>Solr: Health check
        alt /tmp/solr-ready exists (was ready once)
            Solr-->>ECS: Liveness only: /solr/ responds
        else Marker exists and requireHealthyCores passes
            Solr->>Solr: touch /tmp/solr-ready
            Solr-->>ECS: HEALTHY
        else Otherwise
            Solr-->>ECS: UNHEALTHY (ignored during startPeriod)
        end
    end
    alt Task became HEALTHY
        ECS->>ECS: Stop one old Solr task
    else Never healthy (about 390s)
        ECS->>ECS: Kill the task, circuit breaker rolls back after repeated failures
    end
    Note over ECS: Afterwards, run solr:prune-dead to clear<br/>the old tasks' down replicas
```

## Utility Lambda operations

Invoke `<namespace>-solr-utils` with `{"operation": ...}`:

* `solr:status` - `CLUSTERSTATUS`, optionally for one `collection`
* `solr:backup` / `solr:list` / `solr:restore` - backups to the S3 repository
* `solr:rebalance` - delete replicas on nodes that have left the cluster, then add
  replicas up to the replication factor (`expand: true` for every live node, or `node` to
  add one on a specific node). Never deletes a collection.
* `solr:prune-dead` - only delete replicas on nodes that have left the cluster
* `solr:ready` / `zookeeper:ready` - check that the live node count matches `solr.nodeCount` / `zookeeper.nodeCount`

## Outputs

* `solr.endpoint` - The service discovery URL of the solr cluster
* `solr.client_security_group` - The security group for solr client access
* `solr.cluster_size` - The size (number of nodes) of the solr cluster
* `zookeeper.servers` - A list of zookeeper servers in `host:port` format
* `zookeeper.client_security_group` - The security group for zookeeper client access

## Remote State

### Direct Access

```
data "terraform_remote_state" "solrcloud" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/solrcloud.tfstate"
  }
}
```

Outputs are available on `data.remote_state.solrcloud.outputs.*`

### Module Access

```
module "solrcloud" {
  source = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "solrcloud"
}
```

Outputs are available on `module.solrcloud.outputs.*`
