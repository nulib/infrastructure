locals {
  connector_spec = { for key, config  in var.sagemaker_configurations : key => {
    name          = "${local.namespace}-${config.name}-embedding"
    description   = "Opensearch Connector for ${config.name}"
    version       = 1
    protocol      = "aws_sigv4"

    credential = {
      roleArn = aws_iam_role.opensearch_connector.arn
    }

    parameters = {
      region          = data.aws_region.current.name
      service_name    = "sagemaker"
    }

    actions = [
      {
        action_type   = "predict"
        method        = "POST"

        headers = {
          "content-type" = "application/json"
        }

        url                     = local.embedding_invocation_url[key]
        post_process_function   = file("${path.module}/opensearch_connector/post-process.painless")
        request_body            = "{\"inputs\": $${parameters.input}}"
      }
    ]
  }}
}

data "aws_iam_policy_document" "opensearch_connector_assume_role" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]

    principals {
      type          = "Service"
      identifiers   = ["opensearchservice.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "opensearch_connector_role" {
  statement {
    effect    = "Allow"
    actions   = [
      "sagemaker:InvokeEndpoint",
      "sagemaker:InvokeEndpointAsync"
    ]
    resources = [ for endpoint in aws_sagemaker_endpoint.serverless_inference : endpoint.arn ]
  }
}

resource "aws_iam_policy" "opensearch_connector" {
  name    = "${local.namespace}-opensearch-connector"
  policy  = data.aws_iam_policy_document.opensearch_connector_role.json
}

resource "aws_iam_role" "opensearch_connector" {
  name                  = "${local.namespace}-opensearch-connector"
  assume_role_policy    = data.aws_iam_policy_document.opensearch_connector_assume_role.json
}

resource "aws_iam_role_policy_attachment" "opensearch_connector" {
  role          = aws_iam_role.opensearch_connector.id
  policy_arn    = aws_iam_policy.opensearch_connector.arn
}

data "aws_iam_policy_document" "deploy_model_lambda" {
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.opensearch_connector.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["es:ESHttpGet", "es:ESHttpPost"]
    resources = ["${aws_opensearch_domain.elasticsearch.arn}/*"]
  }
}

module "deploy_model_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.2.1"

  function_name          = "${local.namespace}-deploy-opensearch-ml-model"
  description            = "Utility lambda to deploy a SageMaker model within Opensearch"
  handler                = "index.handler"
  runtime                = "nodejs18.x"
  source_path            = "${path.module}/deploy_model_lambda"
  timeout                = 30
  attach_policy_json    = true
  policy_json           = data.aws_iam_policy_document.deploy_model_lambda.json

  environment_variables = {
    OPENSEARCH_ENDPOINT = aws_opensearch_domain.elasticsearch.endpoint
  }
}

resource "aws_lambda_invocation" "deploy_model" {
  for_each        = local.connector_spec
  function_name   = module.deploy_model_lambda.lambda_function_name
  lifecycle_scope = "CRUD"

  input = jsonencode({
    namespace         = local.namespace
    connector_spec    = local.connector_spec[each.key]
    model_name        = "${each.value.name}/huggingface/${var.model_repository}"
    model_version     = "1.0.0"
  })
}
