# resource "aws_security_group" "solr9_service" {
#   name        = "${local.namespace}-solr9-service"
#   description = "Solr 9 Service Security Group"
#   vpc_id      = module.core.outputs.vpc.id
# }

# resource "aws_security_group_rule" "solr9_service_egress" {
#   security_group_id   = aws_security_group.solr9_service.id
#   type                = "egress"
#   from_port           = 0
#   to_port             = 65535
#   protocol            = "tcp"
#   cidr_blocks         = ["0.0.0.0/0"]
# }

# resource "aws_security_group_rule" "solr9_service_ingress" {
#   security_group_id   = aws_security_group.solr9_service.id
#   type                = "ingress"
#   from_port           = 8983
#   to_port             = 8983
#   protocol            = "tcp"
#   cidr_blocks         = ["0.0.0.0/0"]
# }

# resource "aws_security_group" "solr9_client" {
#   name        = "${local.namespace}-solr9-client"
#   description = "Solr 9 Client Security Group"
#   vpc_id      = module.core.outputs.vpc.id
# }

# resource "aws_iam_role" "solr9_task_role" {
#   name               = "solr9"
#   assume_role_policy = module.core.outputs.ecs.assume_role_policy
# }

# resource "aws_iam_role_policy_attachment" "solr9_exec_command" {
#   role       = aws_iam_role.solr9_task_role.id
#   policy_arn = module.core.outputs.ecs.allow_exec_command_policy_arn
# }

# resource "aws_ecs_task_definition" "solr9" {
#   family = "solr9"
#   container_definitions = jsonencode([
#     {
#       name                = "solr9"
#       image               = "solr:9-slim"
#       essential           = true
#       dependsOn           = [{
#         containerName = "zookeeper"
#         condition     = "HEALTHY"
#       }]
#       cpu                 = 1536
#       environment = [
#         { name = "SOLR_HEAP",       value = "${1024 * 0.9765625}m" },
#         { name = "SOLR_MODE",       value = "solrcloud"  },
#         { name = "ZK_HOST",         value = "zookeeper:2181" }
#       ]
#       portMappings = [
#         { protocol = "tcp", hostPort = 8983, containerPort = 8983 }
#       ]
#       volumesFrom  = []
#       readonlyRootFilesystem = false
#       logConfiguration = {
#         logDriver = "awslogs"
#         options   = {
#           awslogs-group         = aws_cloudwatch_log_group.solrcloud_logs.name
#           awslogs-region        = data.aws_region.current.name
#           awslogs-stream-prefix = "solr9"
#         }
#       }
#       healthCheck = {
#         command  = ["CMD-SHELL", "wget -q -O /dev/null http://localhost:8983/solr/"]
#         interval = 30
#         retries  = 3
#         timeout  = 5
#       }
#     },
#     {
#       name                = "zookeeper"
#       image               = "zookeeper:3.9"
#       essential           = true
#       cpu                 = 512
#       environment = [
#         { name = "ZOO_4LW_COMMANDS_WHITELIST", value = "*" },
#         { name = "ZOO_INIT_LIMIT",             value = "30" },
#       ]
#       mountPoints  = []
#       volumesFrom  = []
#       readonlyRootFilesystem = false
#       logConfiguration = {
#         logDriver = "awslogs"
#         options   = {
#           awslogs-group         = aws_cloudwatch_log_group.solrcloud_logs.name
#           awslogs-region        = data.aws_region.current.name
#           awslogs-stream-prefix = "solr9-zk"
#         }
#       }
#       healthCheck = {
#         command  = ["CMD-SHELL", "wget -q -O /dev/null http://localhost:8080/commands/stat"]
#         interval = 30
#         retries  = 3
#         timeout  = 5
#       }
#     }  ])

#   task_role_arn            = aws_iam_role.solr9_task_role.arn
#   execution_role_arn       = module.core.outputs.ecs.task_execution_role_arn
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = 2048
#   memory                   = 4096
# }

# resource "aws_service_discovery_service" "solr9" {
#   name = "solr9"

#   dns_config {
#     namespace_id = module.core.outputs.vpc.service_discovery_dns_zone.id
#     dns_records {
#       ttl  = 10
#       type = "A"
#     }

#     routing_policy = "MULTIVALUE"
#   }
# }

# resource "aws_ecs_service" "solr9" {
#   name                   = "solr9"
#   cluster                = aws_ecs_cluster.solrcloud.id
#   task_definition        = aws_ecs_task_definition.solr9.arn
#   desired_count          = 1
#   enable_execute_command = true
#   launch_type            = "FARGATE"
#   platform_version       = "1.4.0"
  
#   lifecycle {
#     ignore_changes          = [desired_count]
#   }

#   network_configuration {
#     subnets          = module.core.outputs.vpc.private_subnets.ids
#     security_groups  = [
#       aws_security_group.solr9_service.id,
#       aws_security_group.zookeeper_client.id
#     ]
#     assign_public_ip = false
#   }

#   service_registries {
#     registry_arn = aws_service_discovery_service.solr9.arn
#   }
# }
