terraform {
  backend "s3" {
    key    = "infrastructure_configuration.tfstate"
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

locals {
#  environment   = module.core.outputs.stack.environment
  namespace     = module.core.outputs.stack.namespace
  prefix        = module.core.outputs.stack.prefix
  tags          = merge(
    module.core.outputs.stack.tags, 
    {
      Component   = "configuration",
      Git         = "github.com/nulib/infrastructure"
      Project     = "Infrastructure"
    }
  )
}

module "core" {
  source    = "../modules/remote_state"
  component = "core"
}
