output "bastion" {
  value = {
    hostname          = "bastion.${aws_route53_zone.public_zone.name}"
    instance          = data.aws_instance.bastion.id
    security_group    = data.aws_security_group.bastion.id
  }
}

output "ecs" {
  value = {
    allow_exec_command_policy_arn   = data.aws_iam_policy.ecs_exec_command.arn
    assume_role_policy              = data.aws_iam_policy_document.ecs_assume_role.json
    registry_url                    = format("%s.dkr.ecr.%s.amazonaws.com", data.aws_caller_identity.current.id, var.aws_region)
    task_execution_role_arn         = data.aws_iam_role.task_execution_role.arn
  }
}

output "stack" {
  value = {
    account_id    = data.aws_caller_identity.current.id
    environment   = local.environment
    name          = var.stack_name
    namespace     = local.namespace
    tags          = merge(var.tags, local.common_tags)
  }
}

output "vpc" {
  value = {
    id                        = module.vpc.vpc_id
    cidr_block                = var.cidr_block
    http_security_group_id    = aws_security_group.internal_http.id

    private_dns_zone = {
      id   = aws_route53_zone.private_zone.id
      name = aws_route53_zone.private_zone.name 
    }

    private_subnets = {
      cidr_blocks   = var.private_subnets
      ids           = module.vpc.private_subnets
    }

    public_dns_zone = {
      id   = aws_route53_zone.public_zone.id
      name = aws_route53_zone.public_zone.name 
    }

    public_subnets = {
      cidr_blocks   = var.public_subnets
      ids           = module.vpc.public_subnets
    }

    service_discovery_dns_zone = {
      hosted_zone_id    = aws_service_discovery_private_dns_namespace.private_service_discovery.hosted_zone
      id                = aws_service_discovery_private_dns_namespace.private_service_discovery.id
      name              = aws_service_discovery_private_dns_namespace.private_service_discovery.name
    }
  }
}
