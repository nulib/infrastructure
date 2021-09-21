terraform {
  backend "s3" {
    key    = "staging-waf.tfstate"
  }
}

provider "aws" { }

module "core" {
  source    = "../modules/remote_state"
  component = "core"
}

locals {
  tags = module.core.outputs.stack.tags
}

resource "aws_wafv2_ip_set" "nul_ip_set" {
  name               = "nul-ips"
  description        = "NU Library IP Addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.secrets.nul_ips
  tags               = local.tags
}

resource "aws_wafv2_ip_set" "rdc_home_ip_set" {
  name               = "rdc-home-ips"
  description        = "Home IP Addresses of RDC Users"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.secrets.rdc_home_ips
  tags               = local.tags
}

resource "aws_wafv2_web_acl" "staging_ip_acl" {
  name        = "staging-ip-acl"
  description = "Protect staging resources using IP restrictions"
  scope       = "REGIONAL"
  tags        = local.tags

  default_action {
    block {}
  }

  rule {
    name     = "allow-nul-ips"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.nul_ip_set.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "Allow_NUL_IPs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "allow-rdc-home-ips"
    priority = 2

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.rdc_home_ip_set.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "Allow_RDC_Home_IPs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "Staging_IP_ACL"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "load_balancer_association" {
  for_each        = toset(local.secrets.load_balancers)
  resource_arn    = each.key
  web_acl_arn     = aws_wafv2_web_acl.staging_ip_acl.arn
}