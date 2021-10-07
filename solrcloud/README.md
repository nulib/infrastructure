## Description

This terraform project includes the resources required to get the Solrcloud (Solr / Zookeeper) cluster running.

## Prerequisites

* [core](../core/README.md)

## Secrets

* `state_bucket` - The bucket containing remote state files (default: `nulterra-state-sandbox`)
* `zookeeper.ensemble_size` - The number of Zookeeper nodes to run (default: `3`)
* `zookeeper.cpu` - The amount of CPU to reserve for each zookeeper instance (default: `256`)
* `zookeeper.memory` - The amount of RAM to reserve for each zookeeper instance (default: `512`)
* `solr.cluster_size` - The number of Solr nodes to run (default: `4`)
* `solr.cpu` - The amount of CPU to reserve for each solr instance (default: `1024`)
* `solr.memory` - The amount of RAM to reserve for each solr instance (default: `2048`)

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
