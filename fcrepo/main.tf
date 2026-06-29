terraform {
  backend "s3" {
    key    = "fcrepo.tfstate"
  }

  required_providers {
    aws = "~> 5.19"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "west"
  region = "us-west-2"

  default_tags {
    tags = local.tags
  }
}

# Set up `module.core.outputs. as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: fcrepo` into the stack tags
locals {
#  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  prefix        = module.core.outputs.stack.prefix
  tags          = merge(
    module.core.outputs.stack.tags, 
    {
      Component   = "fcrepo",
      Git         = "github.com/nulib/infrastructure"
      Project     = "Infrastructure"
    }
  )
}

module "core" {
  source    = "../modules/remote_state"
  component = "core"
}

module "data_services" {
  source    = "../modules/remote_state"
  component = "data_services"
}

data "aws_region" "current" {}
