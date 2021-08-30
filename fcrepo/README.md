## Description

This terraform project includes the resources required to get Fedora 4.7.5 (with S3 persistence) running.

## Prerequisites

* [core](../core/README.md)
* [data_services](../data_services/README.md)

## Variables

* `aws_region` - The region to create resources in (default: `us-east-1`)
* `state_bucket` - The bucket containing remote state files (default: `nulterra-state-sandbox`)

## Outputs

* `endpoint` - The service discovery URL of the Fedora repository

## Remote State

```
data "terraform_remote_state" "fcrepo" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/fcrepo.tfstate"
    region = var.aws_region
  }
}
```
