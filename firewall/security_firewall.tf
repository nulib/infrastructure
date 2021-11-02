locals {
  count_only     = local.secrets.firewall_type != "SECURITY"
  excluded_rules = {
    AWSManagedRulesCommonRuleSet = ["CrossSiteScripting_BODY", "GenericRFI_BODY", "SizeRestrictions_BODY"]
    AWSManagedRulesKnownBadInputsRuleSet = []
  }
}

resource "aws_wafv2_web_acl" "security_firewall" {
  name        = "${local.namespace}-load-balancer-firewall"
  scope       = "REGIONAL"
  tags        = local.tags

  default_action { 
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

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
        name          = "AWSManagedRulesCommonRuleSet"
        vendor_name   = "AWS"

        dynamic "excluded_rule" {
          for_each = toset(local.excluded_rules["AWSManagedRulesCommonRuleSet"])
          iterator = rule
          content {
            name = rule.key
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled    = true
      metric_name                   = "${local.namespace}-load-balancer-firewall-aws-common"
      sampled_requests_enabled      = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

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
        name          = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name   = "AWS"

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
      cloudwatch_metrics_enabled    = true
      metric_name                   = "${local.namespace}-load-balancer-firewall-aws-known-bad-input"
      sampled_requests_enabled      = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.namespace}-load-balancer-firewall"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "security_firewall" {
  for_each        = local.secrets.resources
  resource_arn    = each.value
  web_acl_arn     = aws_wafv2_web_acl.security_firewall.arn
}