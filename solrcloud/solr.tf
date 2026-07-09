resource "aws_security_group" "solr_service" {
  name        = "${local.namespace}-solr-service"
  description = "Solr Service Security Group"
  vpc_id      = module.core.outputs.vpc.id
}

resource "aws_security_group_rule" "solr_service_egress" {
  security_group_id   = aws_security_group.solr_service.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "solr_service_ingress" {
  security_group_id   = aws_security_group.solr_service.id
  type                = "ingress"
  from_port           = 8983
  to_port             = 8983
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group" "solr_client" {
  name        = "${local.namespace}-solr-client"
  description = "Solr Client Security Group"
  vpc_id      = module.core.outputs.vpc.id
}

resource "aws_iam_role" "solr_task_role" {
  name               = "solr"
  assume_role_policy = module.core.outputs.ecs.assume_role_policy
}

resource "aws_iam_role_policy_attachment" "solr_exec_command" {
  role       = aws_iam_role.solr_task_role.id
  policy_arn = module.core.outputs.ecs.allow_exec_command_policy_arn
}

resource "aws_iam_role_policy_attachment" "solr_backup_bucket_access" {
  role       = aws_iam_role.solr_task_role.id
  policy_arn = aws_iam_policy.solr_backup_bucket_access.arn
}


resource "aws_ecs_task_definition" "solr" {
  family = "solr"
  container_definitions = jsonencode([
    {
      name                = "solr"
      image               = "solr:9"
      essential           = true
      cpu                 = 1024
      environment = [
        { name = "SOLR_OPTS",       value = "-Dsolr.allowPaths=/data/backup -Ds3.bucket.name=${aws_s3_bucket.solr_backup.bucket} -Ds3.bucket.region=${data.aws_region.current.region}" },
        { name = "SOLR_HEAP",       value = "${1024 * 0.9765625}m" },
        { name = "SOLR_MODE",       value = "solrcloud"  },
        { name = "SOLR_MODULES",    value = "analysis-extras,extraction,s3-repository" },
        { name = "ZK_HOST",         value = join(",", local.zookeeper_servers) }
      ]
      portMappings = [
        { protocol = "tcp", hostPort = 8983, containerPort = 8983 }
      ]
      volumesFrom  = []
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.solrcloud_logs.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "solr"
        }
      }
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O /dev/null http://localhost:8983/solr/"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    }
  ])

  task_role_arn            = aws_iam_role.solr_task_role.arn
  execution_role_arn       = module.core.outputs.ecs.task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
}

resource "aws_service_discovery_service" "solr" {
  name = "solr"

  dns_config {
    namespace_id = module.core.outputs.vpc.service_discovery_dns_zone.id
    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_service" "solr" {
  name                   = "solr"
  cluster                = aws_ecs_cluster.solrcloud.id
  task_definition        = aws_ecs_task_definition.solr.arn
  desired_count          = var.solr_cluster_size
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"
  
  lifecycle {
    ignore_changes          = [desired_count]
  }

  network_configuration {
    subnets          = module.core.outputs.vpc.private_subnets.ids
    security_groups  = [
      aws_security_group.solr_service.id,
      aws_security_group.zookeeper_client.id
    ]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.solr.arn
  }
}
