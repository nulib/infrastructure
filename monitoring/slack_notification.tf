module "notify_slack" {
  source  = "terraform-aws-modules/notify-slack/aws"
  version = "6.1.0"

  create_sns_topic        = true
  sns_topic_name          = "${module.core.outputs.stack.namespace}-slack-notification"
  lambda_function_name    = "${module.core.outputs.stack.namespace}-slack-notification"
  slack_channel           = var.slack_webhook.channel
  slack_username          = var.slack_webhook.username
  slack_webhook_url       = var.slack_webhook.url
}