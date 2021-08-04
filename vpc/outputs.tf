output "private_dns_zone" {
  value = {
    id = aws_route53_zone.private_zone.id
    name = aws_route53_zone.private_zone.name 
  }
}

output "private_subnets" {
  value = var.private_subnets
}

output "public_dns_zone" {
  value = {
    id = aws_route53_zone.public_zone.id
    name = aws_route53_zone.public_zone.name 
  }
}

output "public_subnets" {
  value = var.public_subnets
}

output "vpc_id" {
  value = module.vpc.vpc_id
}