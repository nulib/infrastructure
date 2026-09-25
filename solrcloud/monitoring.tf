# Alarms for collections with no live copy.
#
# 1. Every minute the utility Lambda's solr:metrics publishes SolrCloud/LiveReplicas per
#    collection: `active` replicas on live nodes in the collection's weakest shard, 0 for
#    an expected collection missing from cluster state.
# 2. The join-cluster sidecar logs "no live copy" when a new Solr node skips a shard that
#    exists nowhere else; a metric filter counts those.
#
# Notifications go to var.alarm_topic_arn only when it is set (production); otherwise the
# alarms still change state but notify no one.

locals {
  alarm_actions = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]
}

resource "aws_cloudwatch_event_rule" "solr_metrics" {
  name                = "${local.namespace}-solr-metrics"
  description         = "Publish SolrCloud replica metrics"
  schedule_expression = "rate(1 minute)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "solr_metrics" {
  rule      = aws_cloudwatch_event_rule.solr_metrics.name
  target_id = "SolrMetrics"
  arn       = module.backup_lambda.lambda_function_arn
  input = jsonencode({
    operation   = "solr:metrics"
    collections = local.solr_collections
  })
}

resource "aws_lambda_permission" "allow_solr_metrics" {
  statement_id  = "AllowSolrMetricsFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.backup_lambda.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.solr_metrics.arn
}

# No live copy for 3 straight minutes. Missing data is breaching: if the probe can't read
# CLUSTERSTATUS, Solr (or ZooKeeper) is down, which is just as bad. The 3 minutes ride out
# replicas briefly re-registering after a ZooKeeper reconnect.
resource "aws_cloudwatch_metric_alarm" "solr_collection_no_live_replicas" {
  for_each = toset(local.solr_collections)

  alarm_name          = "${local.namespace}-solr-${each.key}-no-live-replicas"
  alarm_description   = "Solr collection ${each.key} has no active replica on a live node (or Solr can't be reached). Restore from backup if it doesn't recover; see solrcloud/README.md."
  namespace           = "SolrCloud"
  metric_name         = "LiveReplicas"
  dimensions          = { Collection = each.key }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Down to a single copy for 10 minutes: one more node loss away from the alarm above.
resource "aws_cloudwatch_metric_alarm" "solr_collection_single_replica" {
  for_each = toset(local.solr_collections)

  alarm_name          = "${local.namespace}-solr-${each.key}-single-replica"
  alarm_description   = "Solr collection ${each.key} has only one active replica on a live node."
  namespace           = "SolrCloud"
  metric_name         = "LiveReplicas"
  dimensions          = { Collection = each.key }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  comparison_operator = "LessThanThreshold"
  threshold           = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_log_metric_filter" "solr_no_live_copy" {
  name           = "solr-join-cluster-no-live-copy"
  log_group_name = aws_cloudwatch_log_group.solrcloud_logs.name
  pattern        = "\"no live copy\""

  metric_transformation {
    namespace     = "SolrCloud"
    name          = "JoinSkippedShards"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "solr_join_skipped_shards" {
  alarm_name          = "${local.namespace}-solr-join-skipped-shards"
  alarm_description   = "A new Solr node found a shard with no live copy anywhere and skipped it (join-cluster logged \"no live copy\"). Restore the affected collection from backup."
  namespace           = "SolrCloud"
  metric_name         = "JoinSkippedShards"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
