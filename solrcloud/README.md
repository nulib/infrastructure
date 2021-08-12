## Description

This terraform project includes the resources required to get the Solrcloud (Solr / Zookeeper) cluster running.

## Prerequisites

* [core](../core/README.md)
* [containers](../containers/README.md)

## Variables

* `aws_region` - The region to create resources in (default: `us-east-1`)
* `state_bucket` - The bucket containing remote state files (default: `nulterra-state-sandbox`)
* `zookeeper_ensemble_size` - The number of Zookeeper nodes to run (default: `3`)
* `solr_cluster_size` - The number of Solr nodes to run (default: `4`)

## Outputs

* `solr_endpoint` - The service discovery URL of the solr cluster
* `zookeeper_servers` - A list of zookeeper servers in `host:port` format

## Remote State

```
data "terraform_remote_state" "solrcloud" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/solrcloud.tfstate"
    region = var.aws_region
  }
}
```
