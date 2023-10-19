terraform {
  backend "s3" {
    key    = "solrcloud.tfstate"
  }

  required_providers {
    aws = "~> 4.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

# Set up `module.core.outputs. as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: solrcloud` into the stack tags
locals {
#  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  tags          = merge(
    module.core.outputs.stack.tags, 
    {
      Component   = "solrcloud",
      Git         = "github.com/nulib/infrastructure"
      Project     = "Infrastructure"
    }
  )
}

module "core" {
  source    = "../modules/remote_state"
  component = "core"
}

data "aws_region" "current" { }

resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
}

resource "aws_cloudwatch_log_group" "solrcloud_logs" {
  name                = "/ecs/solrcloud"
  retention_in_days   = 3
}
