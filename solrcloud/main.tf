terraform {
  backend "s3" {
    key    = "solrcloud.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Set up `local.vpc` as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: solrcloud` into the stack tags
locals {
  environment   = local.vpc.stack.environment
  namespace     = local.vpc.stack.namespace
  tags          = merge(local.vpc.stack.tags, {Component = "solrcloud"})
  vpc           = data.terraform_remote_state.vpc.outputs
  ecr           = data.terraform_remote_state.ecr.outputs
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "nulterra-state-sandbox"
    key    = "env:/${terraform.workspace}/vpc.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "ecr" {
  backend = "s3"

  config = {
    bucket = "nulterra-state-sandbox"
    key    = "env:/${terraform.workspace}/containers.tfstate"
    region = var.aws_region
  }
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_role" "task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "solrcloud_logs" {
  name = "/ecs/solrcloud"
  tags = local.tags
}
