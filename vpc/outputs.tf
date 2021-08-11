output "bastion" {
  value = {
    instance = data.aws_instance.bastion.id
    security_group = data.aws_security_group.bastion.id
  }
}
output "cidr_block" {
  value = var.cidr_block
}

output "http_security_group_id" {
  value = aws_security_group.internal_http.id
}

output "private_dns_zone" {
  value = {
    id   = aws_route53_zone.private_zone.id
    name = aws_route53_zone.private_zone.name 
  }
}

output "private_subnets" {
  value = var.private_subnets
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_dns_zone" {
  value = {
    id   = aws_route53_zone.public_zone.id
    name = aws_route53_zone.public_zone.name 
  }
}

output "public_subnets" {
  value = var.public_subnets
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "service_discovery_dns_zone" {
  value = {
    id   = aws_service_discovery_private_dns_namespace.private_service_discovery.id
    name = aws_service_discovery_private_dns_namespace.private_service_discovery.name
  }
}

output "stack" {
  value = {
    environment   = local.environment
    name          = var.stack_name
    namespace     = local.namespace
    tags          = var.tags
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}