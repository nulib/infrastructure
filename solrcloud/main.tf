terraform {
  backend "s3" {
    key    = "solrcloud.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Set up `local.core` as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: solrcloud` into the stack tags
locals {
  environment   = local.core.stack.environment
  namespace     = local.core.stack.namespace
  tags          = merge(local.core.stack.tags, {Component = "solrcloud"})
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

resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "solrcloud_logs" {
  name = "/ecs/solrcloud"
  tags = local.tags
}
