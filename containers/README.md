## Description

This terraform project includes the Elastic Container Registry (ECR) resources used by Elastic Container Service (ECS) resources throughout the application stack.

## Variables

* `aws_region` - The region to create resources in (default: `us-east-1`)

## Outputs

* `registry_url` - The URL of the private ECR registry

## Remote State

```
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config {
    bucket = "nulterra-state-sandbox"
    key    = "env:/${terraform.workspace}/containers.tfstate"
    region = var.aws_region
  }
}
```
