terraform {
  backend "s3" {
    key    = "data_services.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Set up `local.core` as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: data_services` into the stack tags
locals {
  environment   = local.core.stack.environment
  namespace     = local.core.stack.namespace
  tags          = merge(local.core.stack.tags, {Component = "data_services"})
  core          = data.terraform_remote_state.core.outputs
}

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/core.tfstate"
    region = var.aws_region
  }
}
