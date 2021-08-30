terraform {
  backend "s3" {
    key    = "fcrepo.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Set up `local.core` as an alias for the VPC remote state
# Create convenience accessors for `environment` and `namespace`
# Merge `Component: fcrepo` into the stack tags
locals {
  environment   = local.core.stack.environment
  namespace     = local.core.stack.namespace
  tags          = merge(local.core.stack.tags, {Component = "fcrepo"})
  core          = data.terraform_remote_state.core.outputs
  data_services = data.terraform_remote_state.data_services.outputs

  java_opts = {
    "fcrepo.postgresql.host" = local.data_services.postgres.address
    "fcrepo.postgresql.port" = local.data_services.postgres.port
    "fcrepo.postgresql.username" = "fcrepo"
    "fcrepo.postgresql.password" = module.fcrepo_schema.password
    "aws.accessKeyId" = aws_iam_access_key.fedora_binary_bucket_access_key.id
    "aws.secretKey" = aws_iam_access_key.fedora_binary_bucket_access_key.secret
    "aws.bucket" = aws_s3_bucket.fedora_binary_bucket.id
  }
}

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/core.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "data_services" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/data_services.tfstate"
    region = var.aws_region
  }
}

resource "aws_ecs_cluster" "fcrepo" {
  name = "fcrepo"
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "fcrepo_logs" {
  name = "/ecs/fcrepo"
  tags = local.tags
}

resource "aws_s3_bucket" "fedora_binary_bucket" {
  bucket = "${local.namespace}-fedora-binaries"

  lifecycle_rule {
    abort_incomplete_multipart_upload_days    = 2
    enabled                                   = true
    id                                        = "purge-deleted-objects"

    expiration {
      days = 0
      expired_object_delete_marker = true
    }

    noncurrent_version_expiration {
      days = 7
    }
  }

  tags   = local.tags
}

resource "aws_iam_user" "fedora_binary_bucket_user" {
  name = "${local.namespace}-fcrepo"
  path = "/system/"
}

resource "aws_iam_access_key" "fedora_binary_bucket_access_key" {
  user = aws_iam_user.fedora_binary_bucket_user.name
}

data "aws_iam_policy_document" "fedora_binary_bucket_access" {
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

    resources = [aws_s3_bucket.fedora_binary_bucket.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.fedora_binary_bucket.arn}/*"]
  }
}

resource "aws_iam_policy" "fedora_binary_bucket_policy" {
  name   = "${local.namespace}-fcrepo-s3-bucket-access"
  policy = data.aws_iam_policy_document.fedora_binary_bucket_access.json
}

resource "aws_iam_user_policy_attachment" "fedora_binary_bucket_user_access" {
  user       = aws_iam_user.fedora_binary_bucket_user.name
  policy_arn = aws_iam_policy.fedora_binary_bucket_policy.arn
}

module "fcrepo_schema" {
  source        = "../modules/dbschema"
  schema        = "fcrepo"
  aws_region    = var.aws_region
  state_bucket  = var.state_bucket
}

resource "aws_security_group" "fcrepo_service" {
  name        = "${local.namespace}-fcrepo-service"
  description = "Fedora Repository Service Security Group"
  vpc_id      = local.core.vpc.id

  tags = local.tags
}

resource "aws_security_group_rule" "fcrepo_service_egress" {
  security_group_id   = aws_security_group.fcrepo_service.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "fcrepo_service_ingress" {
  security_group_id   = aws_security_group.fcrepo_service.id
  type                = "ingress"
  from_port           = 8080
  to_port             = 8080
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group" "fcrepo_client" {
  name        = "${local.namespace}-fcrepo-client"
  description = "Fedora Repository Client Security Group"
  vpc_id      = local.core.vpc.id
  tags        = local.tags
}

resource "aws_iam_role" "fcrepo_task_role" {
  name               = "fcrepo"
  assume_role_policy = local.core.ecs.assume_role_policy
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "fcrepo_binary_bucket_access" {
  role       = aws_iam_role.fcrepo_task_role.id
  policy_arn = aws_iam_policy.fedora_binary_bucket_policy.arn
}

resource "aws_iam_role_policy_attachment" "fcrepo_exec_command" {
  role       = aws_iam_role.fcrepo_task_role.id
  policy_arn = local.core.ecs.allow_exec_command_policy_arn
}

resource "aws_ecs_task_definition" "fcrepo" {
  family = "fcrepo"
  container_definitions = jsonencode([
    {
      name                = "fcrepo"
      image               = "${local.core.ecs.registry_url}/fcrepo4:4.7.5-s3multipart"
      essential           = true
      cpu                 = 1000
      memoryReservation   = 3000
      environment = [
        { 
          name  = "MODESHAPE_CONFIG",
          value = "classpath:/config/jdbc-postgresql-s3/repository.json"
        },
        {
          name  = "JAVA_OPTIONS",
          value = join(" ", [for key, value in local.java_opts : "-D${key}=${value}"])
        }
      ]
      portMappings = [
        { hostPort = 8080, containerPort = 8080 }
      ]
      mountPoints = [
        { sourceVolume = "fcrepo-data", containerPath = "/data" }
      ]
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.fcrepo_logs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "fcrepo"
        }
      }
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O /dev/null --method=OPTIONS http://localhost:8080/rest/"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    }
  ])

  volume {
    name = "fcrepo-data"
  }

  task_role_arn            = aws_iam_role.fcrepo_task_role.arn
  execution_role_arn       = local.core.ecs.task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 3072
  tags                     = local.tags
}

resource "aws_service_discovery_service" "fcrepo" {
  name = "fcrepo"

  dns_config {
    namespace_id = local.core.vpc.service_discovery_dns_zone.id
    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_service" "fcrepo" {
  name                   = "fcrepo"
  cluster                = aws_ecs_cluster.fcrepo.id
  task_definition        = aws_ecs_task_definition.fcrepo.arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"
  
  lifecycle {
    create_before_destroy   = true
    ignore_changes          = [desired_count]
  }

  network_configuration {
    subnets          = local.core.vpc.private_subnets.ids
    security_groups  = [ 
      aws_security_group.fcrepo_service.id,
      local.data_services.postgres.client_security_group
    ]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.fcrepo.arn
  }

  tags = local.tags
}