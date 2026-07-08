locals {
  solr_collections = ["arch", "avr"]
  backup_payload   = jsonencode({
    operation = "backup"
    solr = {
      baseUrl = local.solr_endpoint
    }
  })
}

resource "aws_s3_bucket" "solr_backup" {
  bucket = "${local.namespace}-solr-backup"
}

resource "aws_s3_bucket_lifecycle_configuration" "solr_backup" {
  bucket = aws_s3_bucket.solr_backup.id

  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    filter {} # applies to all objects

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

resource "aws_iam_policy" "solr_backup_bucket_access" {
  name        = "solr-backup-bucket-access"
  description = "Allow Solr & Zookeeper tasks to access backup bucket"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.solr_backup.arn]
      },
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.solr_backup.arn}/*"]
      }
    ]
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
  environment_variables = {
    HONEYBADGER_API_KEY       = var.honeybadger_api_key
    HONEYBADGER_ENV           = var.honeybadger_env
    HONEYBADGER_CHECKIN_ID    = var.honeybadger_checkin_id
  }
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
  count                 = var.backup_schedule == null ? 0 : 1
  name                  = "${local.namespace}-solr-backup"
  description           = "Back up solr collections"
  schedule_expression   = var.backup_schedule
  is_enabled            = true
}

resource "aws_cloudwatch_event_target" "back_up_solr" {
  count       = var.backup_schedule == null ? 0 : 1
  rule        = aws_cloudwatch_event_rule.back_up_solr[0].name
  target_id   = "SolrBackup"
  arn         = module.backup_lambda.lambda_function_arn
  input       = local.backup_payload
}
