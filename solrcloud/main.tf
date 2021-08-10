terraform {
  backend "s3" {
    key    = "solrcloud.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Set up `local.vpc` as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: solrcloud` into the stack tags
locals {
  environment   = local.vpc.stack.environment
  namespace     = local.vpc.stack.namespace
  tags          = merge(local.vpc.stack.tags, {Component = "solrcloud"})
  vpc           = data.terraform_remote_state.vpc.outputs
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "nulterra-state-sandbox"
    key    = "env:/${terraform.workspace}/vpc.tfstate"
    region = var.aws_region
  }
}

