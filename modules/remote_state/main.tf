data "terraform_remote_state" "this" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/${var.component}.tfstate"
  }
}

