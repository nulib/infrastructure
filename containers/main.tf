terraform {
  backend "s3" {
    key    = "containers.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "nulterra-state-sandbox"
    key    = "env:/${terraform.workspace}/vpc.tfstate"
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

locals {
  environment   = local.vpc.stack.environment
  namespace     = local.vpc.stack.namespace
  tags          = merge(local.vpc.stack.tags, {Component = "solrcloud"})
  vpc           = data.terraform_remote_state.vpc.outputs
}

resource "aws_ecr_repository" "nulib_images" {
  for_each                = toset(["arch", "avr", "fcrepo4", "meadow", "solr", "zookeeper"])
  name                    = each.key
  image_tag_mutability    = "MUTABLE"
  tags                    = merge(local.tags, { Component = "containers" })
}