locals {
  solr_collections = ["arch", "avr"]
  backup_payload   = jsonencode({
    operation = "backup"
    solr = {
      baseUrl = local.solr_endpoint
    }
  })
}

module "backup_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 3.3.1"

  function_name          = "${local.namespace}-solr-utils"
  description            = "Utility functions for managing a solr cluster"
  handler                = "index.handler"
  runtime                = "nodejs18.x"
  source_path            = "${path.module}/backup-lambda"
  timeout                = 120
  vpc_subnet_ids         = module.core.outputs.vpc.private_subnets.ids
  vpc_security_group_ids = [
    aws_security_group.solr_client.id,
    module.core.outputs.vpc.http_security_group_id
  ]
  attach_network_policy  = true
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  for_each      = toset(aws_cloudwatch_event_rule.back_up_solr[*].arn)
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.backup_lambda.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = each.key
}

data "aws_iam_policy_document" "solr_backup_rule_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "back_up_solr" {
  count                 = length(var.backup_schedule) > 0 ? 1 : 0
  name                  = "${local.namespace}-solr-backup"
  description           = "Back up solr collections"
  schedule_expression   = var.backup_schedule
  is_enabled            = true
}

resource "aws_cloudwatch_event_target" "back_up_solr" {
  count       = length(var.backup_schedule) > 0 ? 1 : 0
  rule        = aws_cloudwatch_event_rule.back_up_solr[0].name
  target_id   = "SolrBackup"
  arn         = module.backup_lambda.lambda_function_arn
  input       = local.backup_payload
}
