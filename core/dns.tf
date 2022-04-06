data "aws_route53_zone" "hosted_zone" {
  name = var.hosted_zone_name
}

resource "aws_route53_zone" "public_zone" {
  name = join(".", [var.stack_name, var.hosted_zone_name])
  tags = local.tags
}

resource "aws_route53_zone" "private_zone" {
  name = join(".", [var.stack_name, "vpc", var.hosted_zone_name])
  tags = local.tags

  vpc {
    vpc_id     = module.vpc.vpc_id
    vpc_region = data.aws_region.current.name
  }
}

resource "aws_route53_record" "public_zone" {
  zone_id = data.aws_route53_zone.hosted_zone.id
  type    = "NS"
  name    = aws_route53_zone.public_zone.name
  records = aws_route53_zone.public_zone.name_servers
  ttl     = 300
}

resource "aws_service_discovery_private_dns_namespace" "private_service_discovery" {
  name        = "internal.${var.hosted_zone_name}"
  description = "Service Discovery for ${var.stack_name}"
  vpc         = module.vpc.vpc_id
  tags        = local.tags
}
