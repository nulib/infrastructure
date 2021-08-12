terraform {
  backend "s3" {
    key    = "core.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  environment   = coalesce(var.environment, substr(terraform.workspace, 0, 1))
  namespace     = join("-", [var.stack_name, local.environment])
  tags          = merge(var.tags, {Component = "core"})
}

data "aws_caller_identity" "current" {}