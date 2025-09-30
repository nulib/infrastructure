locals {
  env = coalesce(var.environment, terraform.workspace)
}

data "terraform_remote_state" "this" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "env:/${local.env}/${var.component}.tfstate"
  }
}

