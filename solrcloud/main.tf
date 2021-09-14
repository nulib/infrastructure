terraform {
  backend "s3" {
    key    = "solrcloud.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Set up `module.core.outputs. as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: solrcloud` into the stack tags
locals {
  environment   = module.core.outputs.stack.environment
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

resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "solrcloud_logs" {
  name = "/ecs/solrcloud"
  tags = local.tags
}
