## Description

This terraform module reads secrets from the [AWS Server Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html).

## Usage

### Project Setup

Invoke the module with defaults from the project's `secrets.tf`:
```
locals {
  secrets = module.secrets.vars
}

module "secrets" {
  source    = "git::https://github.com/nulib/infrastructure.git//modules/secrets"
  path      = "my_project_name"
  defaults  = jsonencode({
    variable_with_default = "default-value"
    tags                  = {}
  })
}
```

### Setting Secret Values

To set or override the values in SSM:
```shell
$ aws ssm put-parameter \
  --name /tfvars/my_project_name \
  --type SecureString \
  --value '{"variable_with_default": "non-default-value", "variable_without_default": "required-value"}'
  --overwrite
```

### Using Secret Values

Use secrets in the project's `main.tf`:
```
resource "aws_s3_bucket" "bucket_with_default_name" {
  bucket = "project-bucket-${local.secrets.variable_with_default}"
  tags   = local.secrets.tags
}

resource "aws_s3_bucket" "bucket_with_required_name" {
  bucket = "project-bucket-${local.secrets.variable_without_default}"
  tags   = local.secrets.tags
}
```
