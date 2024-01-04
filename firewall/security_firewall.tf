locals {
  count_only = var.firewall_type != "SECURITY"
  excluded_rules = {
    AWSManagedRulesCommonRuleSet         = ["CrossSiteScripting_BODY", "GenericRFI_BODY", "SizeRestrictions_BODY"]
    AWSManagedRulesKnownBadInputsRuleSet = []
    AWSManagedRulesBotControlRuleSet     = ["CategoryHttpLibrary", "SignalNonBrowserUserAgent"]
  }
}

resource "aws_cloudwatch_log_group" "security_firewall_log" {
  name                = "aws-waf-logs-${local.namespace}-load-balancer-firewall"
  retention_in_days   = 7
  tags                = local.tags
}

resource "aws_wafv2_web_acl" "security_firewall" {
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

  rule {
    name     = "${local.namespace}-allow-nul-ips"
    priority = 0

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
      metric_name                = "${local.namespace}-allow-nul-ips"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-${local.namespace}-allow-nul-ips-v6"
    priority = 1

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
      metric_name                = "${local.namespace}-allow-nul-ips"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "${local.namespace}-allowed-user-agents"
    priority = 2

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
                  name                = "user-agent"
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

  # Reputation Lists
  # Exempt the Meadow API from any rate limits defined later
  rule {
    name     = "${local.namespace}-allow-meadow-api"
    priority = 3

    action {
      allow {}
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            positional_constraint = "CONTAINS"
            search_string         = "meadow"
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

        statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "/api/"

            field_to_match {

              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-allow-meadow-api"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AmazonIPReputationList"
    priority = 4

    override_action {
      dynamic "none" {
        for_each = toset(local.count_only ? [] : [1])
        content {}
      }

      dynamic "count" {
        for_each = toset(local.count_only ? [1] : [])
        content {}
      }
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
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 5

    override_action {
      dynamic "none" {
        for_each = toset(local.count_only ? [] : [1])
        content {}
      }

      dynamic "count" {
        for_each = toset(local.count_only ? [1] : [])
        content {}
      }
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
    priority = 6

    action {
      dynamic "block" {
        for_each = toset(local.count_only ? [] : [1])
        content {}
      }

      dynamic "count" {
        for_each = toset(local.count_only ? [1] : [])
        content {}
      }
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
  
  # Block requests from a single IP exceeding 750 requests per 5 minute period
  rule {
    name     = "${local.namespace}-rate-limiter"
    priority = 7

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
        limit              = 300
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.namespace}-rate-limiter"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 8

    override_action {
      dynamic "none" {
        for_each = toset(local.count_only ? [] : [1])
        content {}
      }

      dynamic "count" {
        for_each = toset(local.count_only ? [1] : [])
        content {}
      }
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
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 9

    override_action {
      dynamic "none" {
        for_each = toset(local.count_only ? [] : [1])
        content {}
      }

      dynamic "count" {
        for_each = toset(local.count_only ? [1] : [])
        content {}
      }
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
  log_destination_configs = [aws_cloudwatch_log_group.security_firewall_log.arn]
  resource_arn            = aws_wafv2_web_acl.security_firewall.arn

  logging_filter {
    default_behavior = "KEEP"

    filter {
      requirement   = "MEETS_ANY"
      behavior      = "DROP"

      condition {
        action_condition {
          action = "ALLOW"
        }
      }
    }
  }
}

resource "aws_wafv2_web_acl_association" "security_firewall" {
  for_each     = var.firewall_type == "SECURITY" ? var.resources : {}
  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.security_firewall.arn
}
