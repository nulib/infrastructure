terraform {
  backend "s3" {
    key    = "data_services.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Set up `module.core.outputs. as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: data_services` into the stack tags
locals {
  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  tags          = merge(module.core.outputs.stack.tags, {Component = "data_services"})
}

module "core" {
  source    = "../modules/remote_state"
  component = "core"
}
