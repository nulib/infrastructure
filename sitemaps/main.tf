terraform {
  backend "s3" {
    key    = "sitemaps.tfstate"
  }

  required_providers {
    aws    = "~> 4.0"
    random = ">= 3.4.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

locals {
#  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  tags          = merge(
    module.core.outputs.stack.tags, 
    {
      Component   = "sitemaps",
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
