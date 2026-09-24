terraform {
  backend "s3" {
    key    = "solrcloud.tfstate"
  }

  required_providers {
    aws = "~> 6.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

# The custom zookeeper image is gone (a stock image plus the zk-backup sidecar replaced
# it). Forget its build resources without destroying anything: keep_remotely was already
# set, and the pushed image stays in ECR.
removed {
  from = docker_image.zookeeper
  lifecycle {
    destroy = false
  }
}

removed {
  from = docker_registry_image.zookeeper
  lifecycle {
    destroy = false
  }
}

# Set up `module.core.outputs. as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: solrcloud` into the stack tags
locals {
#  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  prefix        = module.core.outputs.stack.prefix
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
data "aws_caller_identity" "current" { }

resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
}

resource "aws_cloudwatch_log_group" "solrcloud_logs" {
  name                = "/ecs/solrcloud"
  retention_in_days   = 14
}
