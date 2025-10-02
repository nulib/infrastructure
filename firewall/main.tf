terraform {
  backend "s3" {
    key    = "firewall.tfstate"
  }

  required_providers {
    aws = "~> 5.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" { }

module "core" {
  source = "../modules/remote_state"
  component = "core"
}

locals {
  namespace           = module.core.outputs.stack.namespace
  ip_firewall         = var.firewall_type == "IP"
  security_firewall   = var.firewall_type == "SECURITY"

  tags = merge(
    module.core.outputs.stack.tags,
    {
      Component   = "firewall"
      Git         = "github.com/nulib/infrastructure"
      Project     = "infrastructure"
    }
  )
}

resource "random_bytes" "security_header_value" {
  length = 16
}

resource "aws_secretsmanager_secret" "firewall_secret" {
  name        = "${terraform.workspace}/infrastructure/firewall"
  description = "Secret value for the x-nul-passkey header to access staging and production applications"
  tags        = local.tags
}

resource "aws_secretsmanager_secret_version" "firewall_secret_version" {
  secret_id     = aws_secretsmanager_secret.firewall_secret.id
  secret_string = jsonencode({
    security_header = {
      name  = "x-nul-${terraform.workspace}-passkey"
      value = random_bytes.security_header_value.hex
    }
  })
}