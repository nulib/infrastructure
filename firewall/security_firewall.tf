locals {
  excluded_rules = {
    AWSManagedRulesCommonRuleSet         = ["CrossSiteScripting_BODY", "GenericRFI_BODY", "SizeRestrictions_BODY"]
    AWSManagedRulesKnownBadInputsRuleSet = []
    AWSManagedRulesBotControlRuleSet     = ["CategoryHttpLibrary", "SignalNonBrowserUserAgent"]
  }
}

resource "aws_cloudwatch_log_group" "security_firewall_log" {
  name              = "aws-waf-logs-${local.namespace}-load-balancer-firewall"
  retention_in_days = 7
  tags              = local.tags
}

resource "aws_wafv2_web_acl" "security_firewall" {
  count = local.security_firewall ? 1 : 0
  name  = "${local.namespace}-load-balancer-firewall"
  scope = "REGIONAL"
  tags  = local.tags

  default_action {
    allow {}
  }

  custom_response_body {
    key          = "rate_limit_response"
    content      = "Rate Limit Exceeded"
    content_type = "TEXT_PLAIN"
  }

  custom_response_body {
    key          = "meadow_access_denied"
    content      = file("${path.module}/meadow_403.html")
    content_type = "TEXT_HTML"
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
    name     = "${local.namespace}-allow-nul-staff-ips"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.nul_staff_ip_set.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-allow-nul-staff-ips"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-block-meadow-access"
    priority = 2

    action {
      block {
        custom_response {
          custom_response_body_key = "meadow_access_denied"
          response_code            = 403
        }
      }
    }

    statement {
      or_statement {
        statement {
          size_constraint_statement {
            field_to_match {
              single_header {
                name = "host"
              }
            }

            comparison_operator = "EQ"
            size                = 0

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "meadow."
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-block-meadow-access"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-allow-nul-ips"
    priority = 3

    rule_label {
      name = "nul:internal-ip:v4"
    }

    action {
      count {}
    }


    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.nul_ip_set.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-allow-nul-ips"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-${local.namespace}-allow-nul-ips-v6"
    priority = 4

    rule_label {
      name = "nul:internal-ip:v6"
    }

    action {
      count {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.nul_ipv6_set.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-allow-nul-ips"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-allowed-user-agents"
    priority = 5

    action {
      allow {}
    }

    statement {
      or_statement {
        dynamic "statement" {
          for_each = toset(var.allowed_user_agents)
          iterator = user_agent
          content {
            byte_match_statement {
              positional_constraint = "EXACTLY"
              search_string         = user_agent.key
              field_to_match {
                single_header {
                  name = "user-agent"
                }
              }
              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }
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
    name     = "${local.namespace}-aws-managed-ip-reputation-list"
    priority = 6

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-load-balancer-firewall-aws-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-aws-managed-bot-control"
    priority = 7

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = toset(local.excluded_rules["AWSManagedRulesBotControlRuleSet"])
          iterator = rule
          content {
            action_to_use {
              count {}
            }

            name = rule.key
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-load-balancer-firewall-aws-bot-control"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-high-traffic-ips"
    priority = 8

    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.high_traffic_ip_set.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-load-balancer-high-traffic-ips"
      sampled_requests_enabled   = true
    }
  }

  # Challenge browsers that exceed the rate limit
  rule {
    name     = "${local.namespace}-browser-rate-limiter"
    priority = 9

    action {
      challenge {}
    }

    statement {
      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = 1000

        scope_down_statement {
          not_statement {
            statement {
              label_match_statement {
                scope = "LABEL"
                key   = "awswaf:managed:aws:bot-control:signal:non_browser_user_agent"
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-rate-limiter"
      sampled_requests_enabled   = true
    }
  }

  # Rate limit (HTTP status 429) HTTP client libraries that exceed the rate limit
  rule {
    name     = "${local.namespace}-http-client-rate-limiter"
    priority = 10

    action {
      block {
        custom_response {
          custom_response_body_key = "rate_limit_response"
          response_code            = 429
        }
      }
    }

    statement {
      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = 500

        scope_down_statement {
          label_match_statement {
            scope = "LABEL"
            key   = "awswaf:managed:aws:bot-control:signal:non_browser_user_agent"
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-rate-limiter"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-aws-managed-common"
    priority = 11

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = toset(local.excluded_rules["AWSManagedRulesCommonRuleSet"])
          iterator = rule
          content {
            action_to_use {
              count {}
            }

            name = rule.key
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-load-balancer-firewall-aws-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-aws-managed-known-bad-inputs"
    priority = 12

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"

        dynamic "excluded_rule" {
          for_each = toset(local.excluded_rules["AWSManagedRulesKnownBadInputsRuleSet"])
          iterator = rule
          content {
            name = rule.key
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-load-balancer-firewall-aws-known-bad-input"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.namespace}-load-balancer-firewall"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "security_firewall" {
  count                   = local.security_firewall ? 1 : 0
  log_destination_configs = [aws_cloudwatch_log_group.security_firewall_log.arn]
  resource_arn            = aws_wafv2_web_acl.security_firewall[0].arn
}

resource "aws_wafv2_web_acl_association" "security_firewall" {
  for_each     = local.security_firewall ? var.resources : {}
  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.security_firewall[0].arn
}
