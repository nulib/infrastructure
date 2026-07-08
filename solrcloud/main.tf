terraform {
  backend "s3" {
    key    = "solrcloud.tfstate"
  }

  required_providers {
    aws = "~> 4.0"
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.5.0"
    }
  }
  required_version = ">= 1.3.0"
}

data "aws_ecr_authorization_token" "registry" {}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

provider "docker" {
  registry_auth {
    address  = data.aws_ecr_authorization_token.registry.proxy_endpoint
    username = data.aws_ecr_authorization_token.registry.user_name
    password = data.aws_ecr_authorization_token.registry.password
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

resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
}

resource "aws_cloudwatch_log_group" "solrcloud_logs" {
  name                = "/ecs/solrcloud"
  retention_in_days   = 3
}
