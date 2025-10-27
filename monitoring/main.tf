terraform {
  backend "s3" {
    key    = "monitoring.tfstate"
  }

  required_providers {
    aws    = "~> 6.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

module "core" {
  source = "../modules/remote_state"
  component = "core"
}

locals {
  alarm_actions = concat(var.alarm_actions, var.slack_webhook.url == "" ? [] : [module.notify_slack.slack_topic_arn])

  tags = merge(
    module.core.outputs.stack.tags,
    {
      Component   = "monitoring"
      Git         = "github.com/nulib/infrastructure"
      Project     = "infrastructure"
    }
  )
}

data "aws_lb" "load_balancer" {
  for_each    = toset(var.load_balancers)
  name        = each.key
}

locals {
  keys = flatten([ for cluster, services in var.services : [ for service in services : "${cluster}.${service}" ] ])
  values = flatten([ for cluster, services in var.services : [ for service in services : { cluster: cluster, service: service } ] ])
  services = zipmap(local.keys, local.values)
}

resource "aws_cloudwatch_metric_alarm" "load_balancer_5xx" {
  for_each              = toset(var.load_balancers)

  actions_enabled       = var.actions_enabled
  alarm_actions         = local.alarm_actions
  alarm_name            = "${each.key}-LoadBalancer5XX"
  comparison_operator   = "GreaterThanOrEqualToThreshold"
  evaluation_periods    = 3
  metric_name           = "HTTPCode_ELB_5XX_Count"
  namespace             = "AWS/ApplicationELB"
  period                = 60
  statistic             = "Sum"
  threshold             = 180
  treat_missing_data    = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.load_balancer[each.key].arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  for_each              = local.services

  actions_enabled       = var.actions_enabled
  alarm_actions         = local.alarm_actions
  alarm_name            = "${each.value.service}-CPUUtilization"
  comparison_operator   = "GreaterThanOrEqualToThreshold"
  evaluation_periods    = 3
  metric_name           = "CPUUtilization"
  namespace             = "AWS/ECS"
  period                = 60
  statistic             = "Average"
  threshold             = 90

  dimensions = {
    ClusterName = each.value.cluster
    ServiceName = each.value.service
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  for_each              = local.services

  actions_enabled       = var.actions_enabled
  alarm_actions         = local.alarm_actions
  alarm_name            = "${each.value.service}-MemoryUtilization"
  comparison_operator   = "GreaterThanOrEqualToThreshold"
  evaluation_periods    = 3
  metric_name           = "MemoryUtilization"
  namespace             = "AWS/ECS"
  period                = 60
  statistic             = "Average"
  threshold             = 90

  dimensions = {
    ClusterName = each.value.cluster
    ServiceName = each.value.service
  }
}

data "aws_route53_zone" "status_zone" {
  name = var.status_zone_name
}

resource "aws_route53_record" "honeybadger_status_page" {
  zone_id   = data.aws_route53_zone.status_zone.id
  name      = "status.${data.aws_route53_zone.status_zone.name}"
  type      = "CNAME"
  records   = ["status.hbuptime.com"]
  ttl       = 300
}