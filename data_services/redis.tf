resource "aws_security_group" "redis_service" {
  name   = "${local.namespace}-redis-service"
  vpc_id = module.core.outputs.vpc.id
  tags   = local.tags
}

resource "aws_security_group" "redis_client" {
  name   = "${local.namespace}-redis-client"
  vpc_id = module.core.outputs.vpc.id
  tags   = local.tags
}

resource "aws_security_group_rule" "redis_egress" {
  security_group_id = aws_security_group.redis_service.id
  type              = "egress"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "redis_ingress" {
  security_group_id           = aws_security_group.redis_service.id
  type                        = "ingress"
  from_port                   = "6379"
  to_port                     = "6379"
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.redis_client.id
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.namespace}-redis"
  subnet_ids = module.core.outputs.vpc.private_subnets.ids
  tags       = local.tags
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.namespace}-redis"
  engine               = "redis"
  node_type            = "cache.t2.small"
  num_cache_nodes      = 1
  engine_version       = "5.0.3"
  security_group_ids   = [aws_security_group.redis_service.id]
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  tags                 = local.tags

  lifecycle {
    ignore_changes = [ engine_version ]
  }
}

resource "aws_route53_record" "redis" {
  zone_id = module.core.outputs.vpc.private_dns_zone.id
  name    = "redis.${module.core.outputs.vpc.private_dns_zone.name}"
  type    = "CNAME"
  ttl     = 900
  records = aws_elasticache_cluster.redis.cache_nodes[*].address
}
