# One ZooKeeper ensemble member: task definition, Cloud Map service, and ECS service.
#
# The root module instantiates this once per node, each depending on the one before, and
# wait_for_steady_state makes Terraform wait for each node to be healthy (part of a
# serving quorum) before rolling the next. minimum 0 / maximum 100 stops the old task
# before starting the new one, so a myid never has two live servers. See
# DEPLOYMENT_UPDATE.md.

locals {
  log_options = {
    awslogs-group  = var.log_group
    awslogs-region = var.region
  }
}

resource "aws_ecs_task_definition" "this" {
  family = "zookeeper-${var.id}"
  container_definitions = jsonencode([
    {
      name      = "zookeeper"
      image     = var.image
      essential = true
      environment = [
        { name = "ZOO_4LW_COMMANDS_WHITELIST", value = "*" },
        { name = "ZOO_INIT_LIMIT",             value = "30" },
        { name = "ZOO_MY_ID",                  value = tostring(var.id) },
        { name = "ZOO_SERVERS",                value = var.zoo_servers },
        { name = "ZOO_STANDALONE_ENABLED",     value = "false" },
        { name = "ZOO_CFG_EXTRA",              value = "electionPortBindRetry=0" }
      ]
      mountPoints = [
        { sourceVolume = "data",    containerPath = "/data",    readOnly = false },
        { sourceVolume = "datalog", containerPath = "/datalog", readOnly = false },
        { sourceVolume = "gate",    containerPath = "/gate",    readOnly = true }
      ]
      volumesFrom = []
      portMappings = [
        { protocol = "tcp", hostPort = 8080, containerPort = 8080 },
        { protocol = "tcp", hostPort = 2181, containerPort = 2181 },
        { protocol = "tcp", hostPort = 2888, containerPort = 2888 },
        { protocol = "tcp", hostPort = 3888, containerPort = 3888 }
      ]
      dependsOn = [
        { containerName = "zk-backup", condition = "HEALTHY" }
      ]
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options, { awslogs-stream-prefix = "zk" })
      }
      healthCheck = {
        command     = ["CMD", "bash", "-c", file("${path.module}/../zookeeper-sidecar/healthcheck.sh")]
        interval    = 15
        retries     = 4
        timeout     = 20
        startPeriod = 120
      }
    },
    {
      name        = "zk-backup"
      image       = var.sidecar_image
      essential   = false
      entryPoint  = ["bash", "-c"]
      command     = [file("${path.module}/../zookeeper-sidecar/backup.sh")]
      stopTimeout = 60
      environment = [
        { name = "S3_BUCKET",       value = var.backup_bucket },
        { name = "S3_PREFIX",       value = "zk" },
        { name = "BACKUP_INTERVAL", value = tostring(var.backup_interval) },
        { name = "ZK_ADMIN_AUTH",   value = var.admin_auth },
        { name = "ZOO_MY_ID",       value = tostring(var.id) },
        { name = "ZOO_SERVERS",     value = var.zoo_servers }
      ]
      mountPoints = [
        { sourceVolume = "data",    containerPath = "/data",    readOnly = false },
        { sourceVolume = "datalog", containerPath = "/datalog", readOnly = false },
        { sourceVolume = "gate",    containerPath = "/gate",    readOnly = false }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options, { awslogs-stream-prefix = "zk-backup" })
      }
      # Healthy once the restore decision is made; the zookeeper container waits for it
      healthCheck = {
        command     = ["CMD-SHELL", "test -f /gate/ready"]
        interval    = 5
        retries     = 3
        timeout     = 2
        startPeriod = 300
      }
    }
  ])

  volume {
    name = "data"
  }

  volume {
    name = "datalog"
  }

  volume {
    name = "gate"
  }

  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
}

resource "aws_service_discovery_service" "this" {
  name = "zookeeper-${var.id}"

  dns_config {
    namespace_id = var.discovery_namespace_id
    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_service" "this" {
  name                   = var.service_name
  cluster                = var.cluster_id
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  wait_for_steady_state              = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this.arn
  }
}
