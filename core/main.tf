terraform {
  backend "s3" {
    key    = "core.tfstate"
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
