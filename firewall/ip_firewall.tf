resource "aws_wafv2_web_acl" "ip_firewall" {
  count       = local.ip_firewall ? 1 : 0
  name        = "staging-ip-acl"
  description = "Protect staging resources using IP restrictions"
  scope       = "REGIONAL"
  tags        = local.tags

  default_action {
    block {}
  }

  rule {
    name     = "${local.namespace}-allow-honeybadger"
    priority = 0

    action {
      allow {}
    }

    statement {
      regex_match_statement {
        regex_string = join("|", var.honeybadger_tokens)
        field_to_match {
          single_header {
            name = "honeybadger-token"
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-allow-honeybadger"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-allow-security-header"
    priority = 3

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        field_to_match {
          single_header {
            name = "x-nul-${terraform.workspace}-passkey"
          }
        }

        positional_constraint = "EXACTLY"
        search_string         = random_bytes.security_header_value.hex

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-allow-security-header"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "allow-nul-ips"
    priority = 10

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
    name     = "allow-nul-ips-v6"
    priority = 20

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.nul_ipv6_set.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "Allow_NUL_IPv6s"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "Staging_IP_ACL"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "ip_firewall" {
  for_each        = local.ip_firewall ? var.resources : {}
  resource_arn    = each.value
  web_acl_arn     = aws_wafv2_web_acl.ip_firewall[0].arn
}