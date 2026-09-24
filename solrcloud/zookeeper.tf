resource "aws_iam_role" "zookeeper_task_role" {
  name               = "zookeeper"
  assume_role_policy = module.core.outputs.ecs.assume_role_policy
}

resource "aws_iam_role_policy_attachment" "zookeeper_exec_command" {
  role       = aws_iam_role.zookeeper_task_role.id
  policy_arn = module.core.outputs.ecs.allow_exec_command_policy_arn
}

resource "aws_iam_role_policy_attachment" "zookeeper_backup_bucket_access" {
  role       = aws_iam_role.zookeeper_task_role.id
  policy_arn = aws_iam_policy.solr_backup_bucket_access.arn
}

resource "aws_security_group" "zookeeper_service" {
  name        = "${local.namespace}-zookeeper-service"
  description = "Zookeeper Service Security Group"
  vpc_id      = module.core.outputs.vpc.id
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

# Members probe each other's client port (`srvr`): the zk-backup sidecar to decide between
# joining and restoring, and the health check to tell "still syncing" from "cold start".
# Without this, those probes time out, and a syncing member looks like a cold start and
# reports healthy.
resource "aws_security_group_rule" "zookeeper_peer_client_ingress" {
  security_group_id        = aws_security_group.zookeeper_service.id
  type                     = "ingress"
  from_port                = 2181
  to_port                  = 2181
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.zookeeper_service.id
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
}

locals {
  # Fixed at 3: each member is its own module below, rolled one after another
  zookeeper_ensemble_size = 3

  zookeeper_hosts    = formatlist("zookeeper-%s.${module.core.outputs.vpc.service_discovery_dns_zone.name}", range(1, local.zookeeper_ensemble_size+1))
  zookeeper_ensemble = [for index, server in local.zookeeper_hosts : "server.${index+1}=${server}:2888:3888;2181"]
  zookeeper_servers  = [for server in local.zookeeper_hosts : "${server}:2181"]

  zookeeper_node = {
    cluster_id             = aws_ecs_cluster.solrcloud.id
    image                  = var.zookeeper_image
    sidecar_image          = var.zookeeper_sidecar_image
    zoo_servers            = join(" ", local.zookeeper_ensemble)
    admin_auth             = "digest super:${var.default_zk_password}"
    backup_bucket          = aws_s3_bucket.solr_backup.bucket
    backup_interval        = 360
    task_role_arn          = aws_iam_role.zookeeper_task_role.arn
    execution_role_arn     = module.core.outputs.ecs.task_execution_role_arn
    log_group              = aws_cloudwatch_log_group.solrcloud_logs.name
    region                 = data.aws_region.current.region
    subnet_ids             = module.core.outputs.vpc.private_subnets.ids
    security_group_ids     = [aws_security_group.zookeeper_service.id]
    discovery_namespace_id = module.core.outputs.vpc.service_discovery_dns_zone.id
  }
}

# Each member waits for the previous one to reach steady state (healthy, part of a
# serving quorum), so a rollout never takes more than one member down at a time.
# Service names keep the original 0-based count index; ids and hostnames are 1-based.

module "zookeeper_1" {
  source       = "./zookeeper-node"
  id           = 1
  service_name = "zookeeper-0"
  depends_on   = [aws_security_group_rule.zookeeper_peer_client_ingress]

  cluster_id             = local.zookeeper_node.cluster_id
  image                  = local.zookeeper_node.image
  sidecar_image          = local.zookeeper_node.sidecar_image
  zoo_servers            = local.zookeeper_node.zoo_servers
  admin_auth             = local.zookeeper_node.admin_auth
  backup_bucket          = local.zookeeper_node.backup_bucket
  backup_interval        = local.zookeeper_node.backup_interval
  task_role_arn          = local.zookeeper_node.task_role_arn
  execution_role_arn     = local.zookeeper_node.execution_role_arn
  log_group              = local.zookeeper_node.log_group
  region                 = local.zookeeper_node.region
  subnet_ids             = local.zookeeper_node.subnet_ids
  security_group_ids     = local.zookeeper_node.security_group_ids
  discovery_namespace_id = local.zookeeper_node.discovery_namespace_id
}

module "zookeeper_2" {
  source       = "./zookeeper-node"
  id           = 2
  service_name = "zookeeper-1"
  depends_on   = [module.zookeeper_1]

  cluster_id             = local.zookeeper_node.cluster_id
  image                  = local.zookeeper_node.image
  sidecar_image          = local.zookeeper_node.sidecar_image
  zoo_servers            = local.zookeeper_node.zoo_servers
  admin_auth             = local.zookeeper_node.admin_auth
  backup_bucket          = local.zookeeper_node.backup_bucket
  backup_interval        = local.zookeeper_node.backup_interval
  task_role_arn          = local.zookeeper_node.task_role_arn
  execution_role_arn     = local.zookeeper_node.execution_role_arn
  log_group              = local.zookeeper_node.log_group
  region                 = local.zookeeper_node.region
  subnet_ids             = local.zookeeper_node.subnet_ids
  security_group_ids     = local.zookeeper_node.security_group_ids
  discovery_namespace_id = local.zookeeper_node.discovery_namespace_id
}

module "zookeeper_3" {
  source       = "./zookeeper-node"
  id           = 3
  service_name = "zookeeper-2"
  depends_on   = [module.zookeeper_2]

  cluster_id             = local.zookeeper_node.cluster_id
  image                  = local.zookeeper_node.image
  sidecar_image          = local.zookeeper_node.sidecar_image
  zoo_servers            = local.zookeeper_node.zoo_servers
  admin_auth             = local.zookeeper_node.admin_auth
  backup_bucket          = local.zookeeper_node.backup_bucket
  backup_interval        = local.zookeeper_node.backup_interval
  task_role_arn          = local.zookeeper_node.task_role_arn
  execution_role_arn     = local.zookeeper_node.execution_role_arn
  log_group              = local.zookeeper_node.log_group
  region                 = local.zookeeper_node.region
  subnet_ids             = local.zookeeper_node.subnet_ids
  security_group_ids     = local.zookeeper_node.security_group_ids
  discovery_namespace_id = local.zookeeper_node.discovery_namespace_id
}

# From the original count-based resources. Moving the Cloud Map services in state (not
# replacing them) matters: deregistering a running task's Cloud Map instance makes ECS
# stop it (see DEPLOYMENT_UPDATE.md).

moved {
  from = aws_ecs_task_definition.zookeeper[0]
  to   = module.zookeeper_1.aws_ecs_task_definition.this
}
moved {
  from = aws_ecs_task_definition.zookeeper[1]
  to   = module.zookeeper_2.aws_ecs_task_definition.this
}
moved {
  from = aws_ecs_task_definition.zookeeper[2]
  to   = module.zookeeper_3.aws_ecs_task_definition.this
}
moved {
  from = aws_service_discovery_service.zookeeper[0]
  to   = module.zookeeper_1.aws_service_discovery_service.this
}
moved {
  from = aws_service_discovery_service.zookeeper[1]
  to   = module.zookeeper_2.aws_service_discovery_service.this
}
moved {
  from = aws_service_discovery_service.zookeeper[2]
  to   = module.zookeeper_3.aws_service_discovery_service.this
}
moved {
  from = aws_ecs_service.zookeeper[0]
  to   = module.zookeeper_1.aws_ecs_service.this
}
moved {
  from = aws_ecs_service.zookeeper[1]
  to   = module.zookeeper_2.aws_ecs_service.this
}
moved {
  from = aws_ecs_service.zookeeper[2]
  to   = module.zookeeper_3.aws_ecs_service.this
}
