resource "aws_iam_role" "zookeeper_task_role" {
  name               = "zookeeper"
  assume_role_policy = module.core.outputs.ecs.assume_role_policy
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "zookeeper_exec_command" {
  role       = aws_iam_role.zookeeper_task_role.id
  policy_arn = module.core.outputs.ecs.allow_exec_command_policy_arn
}

resource "aws_security_group" "zookeeper_service" {
  name        = "${local.namespace}-zookeeper-service"
  description = "Zookeeper Service Security Group"
  vpc_id      = module.core.outputs.vpc.id

  tags = local.tags
}

resource "aws_security_group_rule" "zookeeper_service_egress" {
  security_group_id   = aws_security_group.zookeeper_service.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "zookeeper_service_ingress" {
  for_each = {
    2181 = aws_security_group.zookeeper_client.id
    2888 = aws_security_group.zookeeper_service.id
    3888 = aws_security_group.zookeeper_service.id
  }

  security_group_id        = aws_security_group.zookeeper_service.id
  type                     = "ingress"
  from_port                = each.key
  to_port                  = each.key
  protocol                 = "tcp"
  source_security_group_id = each.value
}

resource "aws_security_group_rule" "zookeeper_service_admin_ingress" {
  security_group_id  = aws_security_group.zookeeper_service.id
  type               = "ingress"
  from_port          = 8080
  to_port            = 8080
  protocol           = "tcp"
  cidr_blocks        = [module.core.outputs.vpc.cidr_block]
}

resource "aws_security_group" "zookeeper_client" {
  name        = "${local.namespace}-zookeeper-client"
  description = "Zookeeper Client Security Group"
  vpc_id      = module.core.outputs.vpc.id
  tags        = local.tags
}

locals {
  zookeeper_hosts = formatlist("zookeeper-%s.${module.core.outputs.vpc.service_discovery_dns_zone.name}", range(1, local.secrets.zookeeper.ensemble_size+1))
  zookeeper_ensemble = [for index, server in local.zookeeper_hosts : "server.${index+1}=${server}:2888:3888;2181"]
  zookeeper_servers  = [for server in local.zookeeper_hosts : "${server}:2181"]
}

resource "aws_ecs_task_definition" "zookeeper" {
  count  = local.secrets.zookeeper.ensemble_size
  family = "zookeeper-${count.index+1}"
  container_definitions = jsonencode([
    {
      name                = "zookeeper"
      image               = "${module.core.outputs.ecs.registry_url}/zookeeper:3.7"
      essential           = true
      cpu                 = 256
      environment = [
        { name = "ZOO_4LW_COMMANDS_WHITELIST", value = "*" },
        { name = "ZOO_INIT_LIMIT",             value = "30" },
        { name = "ZOO_MY_ID",                  value = tostring(count.index+1) },
        { name = "ZOO_SERVERS",                value = replace(join(" ", local.zookeeper_ensemble), "zookeeper-${count.index+1}.${module.core.outputs.vpc.service_discovery_dns_zone.name}", "0.0.0.0") },
        { name = "ZOO_STANDALONE_ENABLED",     value = "false" },
        { name = "ZOO_CFG_EXTRA",              value = "electionPortBindRetry=0" }
      ]
      portMappings = [{
          hostPort        = 8080
          containerPort   = 8080
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
          awslogs-group         = aws_cloudwatch_log_group.solrcloud_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "zk"
        }
      }
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O /dev/null http://localhost:8080/commands/stat"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    }
  ])
  task_role_arn            = aws_iam_role.zookeeper_task_role.arn
  execution_role_arn       = module.core.outputs.ecs.task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  tags                     = local.tags
}

resource "aws_service_discovery_service" "zookeeper" {
  count    = local.secrets.zookeeper.ensemble_size
  name     = "zookeeper-${count.index+1}"

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

resource "aws_ecs_service" "zookeeper" {
  count                  = local.secrets.zookeeper.ensemble_size
  name                   = "zookeeper-${count.index}"
  cluster                = aws_ecs_cluster.solrcloud.id
  task_definition        = aws_ecs_task_definition.zookeeper[count.index].arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"

  lifecycle {
    ignore_changes          = [desired_count]
  }

  network_configuration {
    subnets          = module.core.outputs.vpc.private_subnets.ids
    security_groups  = [aws_security_group.zookeeper_service.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.zookeeper.*.arn[count.index]
  }

  tags = local.tags
}
