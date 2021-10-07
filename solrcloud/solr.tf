resource "aws_efs_file_system" "solr_backup_volume" {
  encrypted      = false
  tags           = merge(local.tags, { Name = "stack-solr-backup"})
}

resource "aws_efs_mount_target" "solr_backup_mount_target" {
  for_each          = toset(module.core.outputs.vpc.private_subnets.ids)
  file_system_id    = aws_efs_file_system.solr_backup_volume.id
  security_groups   = [
    aws_security_group.solr_backup_access.id
  ]
  subnet_id         = each.key
}

resource "aws_security_group" "solr_backup_access" {
  name        = "${local.namespace}-solr-backup"
  description = "Solr Backup Volume Security Group"
  vpc_id      = module.core.outputs.vpc.id

  tags = local.tags
}

resource "aws_security_group_rule" "solr_backup_egress" {
  security_group_id   = aws_security_group.solr_backup_access.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = -1
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "solr_backup_ingress" {
  security_group_id           = aws_security_group.solr_backup_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.solr_service.id
}

resource "aws_security_group_rule" "solr_backup_ingress_bastion" {
  security_group_id           = aws_security_group.solr_backup_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = module.core.outputs.bastion.security_group
}

resource "aws_security_group" "solr_service" {
  name        = "${local.namespace}-solr-service"
  description = "Solr Service Security Group"
  vpc_id      = module.core.outputs.vpc.id

  tags = local.tags
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
  tags        = local.tags
}

resource "aws_iam_role" "solr_task_role" {
  name               = "solr"
  assume_role_policy = module.core.outputs.ecs.assume_role_policy
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "solr_exec_command" {
  role       = aws_iam_role.solr_task_role.id
  policy_arn = module.core.outputs.ecs.allow_exec_command_policy_arn
}

resource "aws_ecs_task_definition" "solr" {
  family = "solr"
  container_definitions = jsonencode([
    {
      name                = "solr"
      image               = "${module.core.outputs.ecs.registry_url}/solr:7.5"
      essential           = true
      cpu                 = local.secrets.solr.cpu
      memoryReservation   = local.secrets.solr.memory
      environment = [
        { name = "SOLR_HEAP",       value = "${local.secrets.solr.memory * 0.9765625}m" },
        { name = "SOLR_MODE",       value = "solrcloud"  },
        { name = "ZK_HOST",         value = join(",", local.zookeeper_servers) }
      ]
      portMappings = [
        { hostPort = 8983, containerPort = 8983 }
      ]
      mountPoints = [
        { sourceVolume = "solr-backup", containerPath = "/data/backup" }
      ]
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.solrcloud_logs.name
          awslogs-region        = data.aws_region.current.name
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

  volume {
    name = "solr-backup"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.solr_backup_volume.id
    }
  }

  task_role_arn            = aws_iam_role.solr_task_role.arn
  execution_role_arn       = module.core.outputs.ecs.task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.secrets.solr.cpu
  memory                   = local.secrets.solr.memory
  tags                     = local.tags
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

  tags = local.tags
}

resource "aws_ecs_service" "solr" {
  name                   = "solr"
  cluster                = aws_ecs_cluster.solrcloud.id
  task_definition        = aws_ecs_task_definition.solr.arn
  desired_count          = local.secrets.solr.cluster_size
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

  tags = local.tags
}

resource "aws_ecs_service" "solr_extra" {
  name                   = "solr-extra"
  cluster                = aws_ecs_cluster.solrcloud.id
  task_definition        = aws_ecs_task_definition.solr.arn
  desired_count          = 0
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

  tags = local.tags
}
