locals {
  fedora6_java_opts = {
    "fcrepo.db.url"         = "jdbc:postgresql://${module.data_services.outputs.postgres.address}:${module.data_services.outputs.postgres.port}/fedora6"
    "fcrepo.db.user"    = "fedora6"
    "fcrepo.db.password"    = module.fedora6_schema.password
    "fcrepo.storage"        = "ocfl-s3"
    "fcrepo.ocfl.s3.region" = data.aws_region.current.name
    "fcrepo.ocfl.s3.bucket" = aws_s3_bucket.fedora6_ocfl_bucket.id
  }

  fcrepo6_admin_user = "fedoraAdmin"
  fcrepo6_admin_pass = "fedoraAdmin"
}

resource "aws_ecs_cluster" "fedora6" {
  name = "fedora6"
}

resource "aws_cloudwatch_log_group" "fedora6_logs" {
  name                = "/ecs/fedora6"
  retention_in_days   = 3
}

resource "aws_s3_bucket" "fedora6_ocfl_bucket" {
  bucket = "${local.namespace}-fedora6-ocfl"
}

resource "aws_s3_bucket_lifecycle_configuration" "fedora6_ocfl_bucket" {
  bucket = aws_s3_bucket.fedora6_ocfl_bucket.id
  rule {
    id     = "purge-deleted-objects"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }

    expiration {
      days = 0
      expired_object_delete_marker = true
    }

    noncurrent_version_expiration {
      noncurrent_days = 730
    }
  }
}

data "aws_iam_policy_document" "fedora6_ocfl_bucket_access" {
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

    resources = [aws_s3_bucket.fedora6_ocfl_bucket.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.fedora6_ocfl_bucket.arn}/*"]
  }
}

resource "aws_iam_policy" "fedora6_ocfl_bucket_policy" {
  name   = "${local.namespace}-fedora6-s3-bucket-access"
  policy = data.aws_iam_policy_document.fedora6_ocfl_bucket_access.json
}

module "fedora6_ocfl_bucket_replication" {
  source              = "../modules/replication"
  count               = module.core.outputs.stack.environment == "p" ? 1 : 0
  source_bucket_arn   = aws_s3_bucket.fedora6_ocfl_bucket.arn
  providers = {
    aws.source = aws
    aws.target = aws.west
  }
}

module "fedora6_schema" {
  source        = "../modules/dbschema"
  schema        = "fedora6"
  bastion_user  = var.bastion_user
}

resource "aws_security_group" "fedora6_service" {
  name        = "${local.namespace}-fedora6-service"
  description = "Fedora Repository Service Security Group"
  vpc_id      = module.core.outputs.vpc.id
}

resource "aws_security_group_rule" "fedora6_service_egress" {
  security_group_id   = aws_security_group.fedora6_service.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "fedora6_service_ingress" {
  security_group_id   = aws_security_group.fedora6_service.id
  type                = "ingress"
  from_port           = 8080
  to_port             = 8080
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group" "fedora6_client" {
  name        = "${local.namespace}-fedora6-client"
  description = "Fedora Repository Client Security Group"
  vpc_id      = module.core.outputs.vpc.id
}

resource "aws_iam_role" "fedora6_task_role" {
  name               = "fedora6"
  assume_role_policy = module.core.outputs.ecs.assume_role_policy
}

resource "aws_iam_role_policy_attachment" "fedora6_ocfl_bucket_access" {
  role       = aws_iam_role.fedora6_task_role.id
  policy_arn = aws_iam_policy.fedora6_ocfl_bucket_policy.arn
}

resource "aws_iam_role_policy_attachment" "fedora6_exec_command" {
  role       = aws_iam_role.fedora6_task_role.id
  policy_arn = module.core.outputs.ecs.allow_exec_command_policy_arn
}

resource "aws_ecs_task_definition" "fedora6" {
  family = "fedora6"
  container_definitions = jsonencode([
    {
      name                = "fedora6"
      image               = "docker.io/fcrepo/fcrepo:6-tomcat9"
      essential           = true
      cpu                 = var.cpu
      memoryReservation   = var.memory
      environment = [
         {
          name  = "JAVA_OPTS",
          value = join(" ", [for key, value in local.fedora6_java_opts : "-D${key}=${value}"])
        }
      ]
      portMappings = [
        { hostPort = 8080, containerPort = 8080 }
      ]
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.fedora6_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "fedora6"
        }
      }
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O /dev/null --method=OPTIONS http://${local.fcrepo6_admin_user}:${local.fcrepo6_admin_pass}@localhost:8080/fcrepo/rest/"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    }
  ])

  task_role_arn            = aws_iam_role.fedora6_task_role.arn
  execution_role_arn       = module.core.outputs.ecs.task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
}

resource "aws_service_discovery_service" "fedora6" {
  name = "fedora6"

  dns_config {
    namespace_id = module.core.outputs.vpc.service_discovery_dns_zone.id
    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_service" "fedora6" {
  name                   = "fedora6"
  cluster                = aws_ecs_cluster.fedora6.id
  task_definition        = aws_ecs_task_definition.fedora6.arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"
  
  lifecycle {
    ignore_changes          = [desired_count]
  }

  network_configuration {
    subnets          = module.core.outputs.vpc.private_subnets.ids
    security_groups  = [ 
      aws_security_group.fedora6_service.id,
      module.data_services.outputs.postgres.client_security_group
    ]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.fedora6.arn
  }
}