terraform {
  backend "s3" {
    key    = "core.tfstate"
  }
}

provider "aws" { }

locals {
  environment   = coalesce(var.environment, substr(terraform.workspace, 0, 1))
  namespace     = join("-", [var.stack_name, local.environment])
  common_tags   = {
    Department  = "RDC"
    Environment = terraform.workspace
    Terraform   = "true"
  }
  tags          = merge(
    merge(var.tags, local.common_tags),
    {
      Component   = "core",
      Git         = "github.com/nulib/infrastructure"
      Project     = "Infrastructure"
    }
  )
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
