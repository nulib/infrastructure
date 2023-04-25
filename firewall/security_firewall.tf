locals {
  count_only = var.firewall_type != "SECURITY"
  excluded_rules = {
    AWSManagedRulesCommonRuleSet         = ["CrossSiteScripting_BODY", "GenericRFI_BODY", "SizeRestrictions_BODY"]
    AWSManagedRulesKnownBadInputsRuleSet = []
  }
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

  # Exempt the Meadow API from any rate limits defined later
  rule {
    name     = "stack-p-allow-meadow-api"
    priority = 0

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
      metric_name                = "stack-p-allow-meadow-api"
      sampled_requests_enabled   = true
    }
  }

  # Block aggressive requests originating in Ireland
  rule {
    name     = "stack-p-aggressive-ie"
    priority = 1

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
        limit              = 150
        aggregate_key_type = "IP"

        scope_down_statement {
          geo_match_statement {
            country_codes = ["IE"]
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "stack-p-aggressive-ie"
      sampled_requests_enabled   = true
    }
  }

  # Block requests from a single IP exceeding 750 requests per 5 minute period
  rule {
    name     = "stack-p-rate-limiter"
    priority = 2

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
        limit              = 750
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "stack-p-rate-limiter"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 3

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

resource "aws_wafv2_web_acl_association" "security_firewall" {
  for_each     = var.resources
  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.security_firewall.arn
}
