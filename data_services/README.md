## Description

This terraform project includes the resources required for the main datastore services (PostgreSQL, Redis, and Elasticsearch).

## Prerequisites

* [core](../core/README.md)

## Variables

* `aws_region` - The region to create resources in (default: `us-east-1`)
* `state_bucket` - The bucket containing remote state files (default: `nulterra-state-sandbox`)
* `postgres_version` - The version of postgres to provision (default: `13.1`)
* `allocated_storage` - The size (in GB) of the allocated DB storage (default: `100`)
* `instance_class` - The DB instance class to create (default: `db.t3.medium`)

## Outputs

* `postgres.address` - The database server address
* `postgres.port` - The database server port
* `postgres.client_security_group` - The ID of the security group for database clients
* `postgres.admin_user` - The database superuser name
* `postgres.admin_password` - The database superuser password

## Remote State

```
data "terraform_remote_state" "data_services" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/data_services.tfstate"
    region = var.aws_region
  }
}
```
