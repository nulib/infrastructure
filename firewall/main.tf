terraform {
  backend "s3" {
    key    = "firewall.tfstate"
  }
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
