## Description

This terraform project includes the resources required for the main datastore services (PostgreSQL, Redis, and Elasticsearch).

## Prerequisites

* [core](../core/README.md)

## Secrets

* `state_bucket` - The bucket containing remote state files (default: `nulterra-state-sandbox`)
* `postgres_version` - The version of postgres to provision (default: `13.1`)
* `allocated_storage` - The size (in GB) of the allocated DB storage (default: `100`)
* `instance_class` - The DB instance class to create (default: `db.t3.medium`)

## Outputs

* `elasticsearch.full_policy_arn` - The ARN of the policy granting read/write access to Elasticsearch
* `elasticsearch.read_policy_arn` - The ARN of the policy granting read access to Elasticsearch
* `elasticsearch.arn` - The ARN of the Elasticsearch domain
* `elasticsearch.endpoint` - The URL of the Elasticsearch service
* `postgres.address` - The database server address
* `postgres.port` - The database server port
* `postgres.client_security_group` - The ID of the security group for database clients
* `postgres.admin_user` - The database superuser name
* `postgres.admin_password` - The database superuser password
* `redis.address` - The address of the Redis cluster
* `redis.port` - The port of the Redis cluster
* `redis.client_security_group` - The ID of the security group for Redis clients

## Remote State

### Direct Access

```
data "terraform_remote_state" "data_services" {
  backend = "s3"

  config {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/data_services.tfstate"
  }
}
```

Outputs are available on `data.remote_state.data_services.outputs.*`

### Module Access

```
module "data_services" {
  source = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "data_services"
}
```

Outputs are available on `module.data_services.outputs.*`
