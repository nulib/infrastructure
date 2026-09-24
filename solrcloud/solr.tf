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


locals {
  solr_gate_marker = "/gate/replicas-active"

  # Until this node has first been ready, require the join-cluster sidecar's marker and
  # every local core active; after that, liveness only. ECS has no separate readiness
  # check, so a replica recovering later mustn't get its node killed.
  solr_health_check = join(" ", [
    "if [ -f /tmp/solr-ready ]; then",
    "wget -q -O /dev/null http://localhost:8983/solr/;",
    "else",
    "[ -f ${local.solr_gate_marker} ] &&",
    "wget -q -O /dev/null 'http://localhost:8983/solr/admin/info/health?requireHealthyCores=true' &&",
    "touch /tmp/solr-ready;",
    "fi"
  ])
}

resource "aws_ecs_task_definition" "solr" {
  family = "solr"
  container_definitions = jsonencode([
    {
      name                = "solr"
      image               = var.solr_image
      essential           = true
      environment = [
        { name = "SOLR_OPTS",           value = "-Dsolr.allowPaths=/data/backup -Ds3.bucket.name=${aws_s3_bucket.solr_backup.bucket} -Ds3.bucket.region=${data.aws_region.current.region}" },
        { name = "SOLR_HEAP",           value = "${var.solr_heap}m" },
        { name = "SOLR_MODE",           value = "solrcloud"  },
        { name = "SOLR_MODULES",        value = "analysis-extras,extraction,s3-repository" },
        { name = "ZK_HOST",             value = join(",", local.zookeeper_servers) }
      ]
      portMappings = [
        { protocol = "tcp", hostPort = 8983, containerPort = 8983 }
      ]
      mountPoints = [
        { sourceVolume = "gate", containerPath = "/gate", readOnly = true }
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
        command     = ["CMD-SHELL", local.solr_health_check]
        interval    = 30
        retries     = 3
        timeout     = 5
        startPeriod = 300
      }
    },
    {
      name        = "join-cluster"
      image       = var.solr_sidecar_image
      essential   = false
      command     = ["python3", "-c", file("${path.module}/solr-sidecar/join_cluster.py")]
      environment = [
        { name = "MARKER_FILE", value = local.solr_gate_marker }
      ]
      mountPoints = [
        { sourceVolume = "gate", containerPath = "/gate", readOnly = false }
      ]
      dependsOn = [
        { containerName = "solr", condition = "START" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.solrcloud_logs.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "join-cluster"
        }
      }
    }
  ])

  volume {
    name = "gate"
  }

  task_role_arn            = aws_iam_role.solr_task_role.arn
  execution_role_arn       = module.core.outputs.ecs.task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.solr_cpu
  memory                   = var.solr_task_memory
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
  # Roll Solr only after every zookeeper member is steady
  depends_on = [module.zookeeper_3]

  name                   = "solr"
  cluster                = aws_ecs_cluster.solrcloud.id
  task_definition        = aws_ecs_task_definition.solr.arn
  desired_count          = var.solr_cluster_size
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

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
