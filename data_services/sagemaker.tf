locals {
  model_container_spec = {
    framework         = "huggingface"
    base_framework    = "pytorch"
    image_scope       = "inference"
    framework_version = "2.1.0"
    image_version     = "4.37.0"
    python_version    = "py310"
    processor         = "cpu"
    image_os          = "ubuntu22.04"
  }

  model_id         = element(split("/", var.model_repository), length(split("/", var.model_repository))-1)
  model_repository = join("-", [local.model_container_spec.framework, local.model_container_spec.base_framework, local.model_container_spec.image_scope])
  model_image_tag  = "${local.model_container_spec.framework_version}-transformers${local.model_container_spec.image_version}-${local.model_container_spec.processor}-${local.model_container_spec.python_version}-${local.model_container_spec.image_os}"

  
  embedding_invocation_url = { for key, value in var.sagemaker_configurations : key => "https://runtime.sagemaker.${data.aws_region.current.name}.amazonaws.com/endpoints/${aws_sagemaker_endpoint.serverless_inference[key].name}/invocations" }
}

resource "aws_s3_bucket" "sagemaker_model_bucket" {
  bucket = "${local.namespace}-model-artifacts"
}

resource "terraform_data" "inference_model_artifact" {
  triggers_replace = [
    var.model_repository
  ]

  input = "${path.module}/model/.working/${local.model_id}.tar.gz"

  provisioner "local-exec" {
    command     = "./build_model.sh"
    working_dir = "${path.module}/model"

    environment = {
      model_id     = local.model_id
      repository   = var.model_repository
      requirements = join("\n", var.model_requirements)
    }
  }
}

resource "aws_s3_object" "inference_model_artifact" {
  bucket       = aws_s3_bucket.sagemaker_model_bucket.bucket
  key          = "custom_inference/${local.model_id}/${local.model_id}.tar.gz"
  source       = terraform_data.inference_model_artifact.output
  content_type = "application/gzip"
}

data "aws_sagemaker_prebuilt_ecr_image" "inference_container" {
  repository_name = local.model_repository
  image_tag       = local.model_image_tag
}

data "aws_iam_policy_document" "embedding_model_execution_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "embedding_model_execution_role" {
  statement {
    effect  = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:CreateLogGroup",
      "logs:DescribeLogStreams",
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.sagemaker_model_bucket.bucket}/${aws_s3_object.inference_model_artifact.key}"]
  }

  statement {
    effect  = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "embedding_model_execution_role" {
  name   = "${local.namespace}-sagemaker-model-execution-role"
  policy = data.aws_iam_policy_document.embedding_model_execution_role.json
}

resource "aws_iam_role" "embedding_model_execution_role" {
  name               = "${local.namespace}-sagemaker-model-execution-role"
  assume_role_policy = data.aws_iam_policy_document.embedding_model_execution_assume_role.json
}

resource "aws_iam_role_policy_attachment" "embedding_model_execution_role" {
  role       = aws_iam_role.embedding_model_execution_role.id
  policy_arn = aws_iam_policy.embedding_model_execution_role.arn
}

resource "aws_sagemaker_model" "embedding_model" {
  name               = "${local.namespace}-embedding-model"
  execution_role_arn = aws_iam_role.embedding_model_execution_role.arn
  
  primary_container {
    image          = data.aws_sagemaker_prebuilt_ecr_image.inference_container.registry_path
    mode           = "SingleModel"
    model_data_url = "s3://${aws_s3_object.inference_model_artifact.bucket}/${aws_s3_object.inference_model_artifact.key}"
  }
}

resource "aws_sagemaker_endpoint_configuration" "serverless_inference" {
  for_each = var.sagemaker_configurations

  name = "${local.namespace}-embedding-model-${each.value.name}"
  
  production_variants {
      model_name   = aws_sagemaker_model.embedding_model.name
      variant_name = "AllTraffic"

      serverless_config {
        memory_size_in_mb       = each.value.memory
        max_concurrency         = each.value.max_concurrency
        provisioned_concurrency = each.value.provisioned_concurrency > 0 ? each.value.provisioned_concurrency : null
      }
  }
}

resource "aws_sagemaker_endpoint" "serverless_inference" {
  for_each             = var.sagemaker_configurations
  name                 = "${local.namespace}-embedding-${each.value.name}"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.serverless_inference[each.key].name
}
