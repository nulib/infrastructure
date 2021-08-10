resource "aws_s3_bucket" "zookeeper_configs" {
  bucket        = "${local.namespace}-zk-configs"
  acl           = "private"
  tags          = local.tags
  force_destroy = true
}

data "aws_iam_policy_document" "zookeeper_config_bucket_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["arn:aws:s3:::*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.zookeeper_configs.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.zookeeper_configs.arn}/*"]
  }
}

resource "aws_iam_policy" "zookeeper_config_bucket_policy" {
  name   = "${local.namespace}-zk-config-bucket-access"
  policy = data.aws_iam_policy_document.zookeeper_config_bucket_access.json
  tags   = local.tags
}

resource "aws_security_group" "zookeeper_service" {
  name        = "${local.namespace}-zookeeper-service"
  description = "Zookeeper Service Security Group"
  vpc_id      = local.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0", "::0/0"]
  }

  ingress {
    from_port         = 2181
    to_port           = 2181
    protocol          = "tcp"
    security_groups   = [aws_security_group.zookeeper_client.id]
  }

  tags = local.tags
}

resource "aws_security_group" "zookeeper_client" {
  name        = "${local.namespace}-zookeeper-client"
  description = "Zookeeper Client Security Group"
  tags        = local.tags
}

resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
  tags = local.tags
}

resource "aws_ecs_task_definition" "zookeeper" {
  family                   = "zookeeper"
  container_definitions    = jsonencode([{
    name                = "zookeeper"
    image               = "nulib/zookeeper-exhibitor:latest"
    essential           = true
    memoryReservation   = 3000
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "S3_BUCKET",  value = aws_s3_bucket.zookeeper_configs.id },
      { name = "S3_PREFIX",  value = ""}
    ]
    portMappings = [{
        hostPort      = 8181
        containerPort = 8181
      },
      {
        hostPort        = 2181
        containerPort   = 2181
      },
      {
        hostPort        = 2888
        containerPort   = 2888
      },
      {
        hostPort        = 3888
        containerPort   = 3888
      }
    ]
    readonlyRootFilesystem = false
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        awslogs-group         = "${local.namespace}-solrcloud}"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "zk"
      }
    }
  }])
  tags = local.tags
}