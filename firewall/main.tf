terraform {
  backend "s3" {
    key    = "firewall.tfstate"
  }

  required_providers {
    aws = "~> 4.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" { }

module "core" {
  source = "../modules/remote_state"
  component = "core"
}

locals {
  namespace = module.core.outputs.stack.namespace
  tags = merge(
    module.core.outputs.stack.tags,
    {
      Component   = "firewall"
      Git         = "github.com/nulib/infrastructure"
      Project     = "infrastructure"
    }
  )
}
