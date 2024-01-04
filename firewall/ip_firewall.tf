resource "aws_wafv2_web_acl" "ip_firewall" {
  count       = var.firewall_type == "IP" ? 1 : 0
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
    name     = "allow-nul-ips-v6"
    priority = 2

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
  rule {
    name     = "allow-rdc-home-ips"
    priority = 3

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

resource "aws_wafv2_web_acl_association" "ip_firewall" {
  for_each        = var.firewall_type == "IP" ? var.resources : {}
  resource_arn    = each.value
  web_acl_arn     = aws_wafv2_web_acl.ip_firewall[0].arn
}