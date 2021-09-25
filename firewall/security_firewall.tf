resource "aws_wafv2_web_acl" "security_firewall" {
  count       = local.secrets.firewall_type == "SECURITY" ? 1 : 0
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
      none {}
    }

    statement {
      managed_rule_group_statement {
        name          = "AWSManagedRulesCommonRuleSet"
        vendor_name   = "AWS"
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
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        name          = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name   = "AWS"
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
  for_each        = toset(local.secrets.firewall_type == "SECURITY" ? local.secrets.load_balancers : [])
  resource_arn    = data.aws_lb.load_balancer[each.key].arn
  web_acl_arn     = aws_wafv2_web_acl.security_firewall[0].arn
}