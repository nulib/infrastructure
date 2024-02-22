terraform {
  backend "s3" {
    key    = "data_services.tfstate"
  }

  required_providers {
    aws    = "~> 5.1"
    random = ">= 3.4.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" { }

# Set up `module.core.outputs. as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: data_services` into the stack tags
locals {
#  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  tags          = merge(
    module.core.outputs.stack.tags, 
    {
      Component   = "data_services",
      Git         = "github.com/nulib/infrastructure"
      Project     = "Infrastructure"
    }
  )
}

module "core" {
  source    = "../modules/remote_state"
  component = "core"
}

data "aws_region" "current" {}

