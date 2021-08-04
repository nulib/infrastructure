terraform {
  backend "s3" {
    key    = "vpc.tfstate"
  }
}

locals {
  environment = coalesce(var.environment, substr(terraform.workspace, 0, 1))
  namespace = join("-", [var.stack_name, local.environment])
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.namespace}-vpc"
  cidr = var.cidr_block

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  single_nat_gateway = true

  create_database_subnet_group = false

  private_subnet_tags = {
    SubnetType = "private"
  }

  public_subnet_tags = {
    SubnetType = "public"
  }

  tags = var.tags
}

data "aws_route53_zone" "hosted_zone" {
  name = var.hosted_zone_name
}

resource "aws_route53_zone" "public_zone" {
  name = join(".", [var.stack_name, var.hosted_zone_name])
  tags = var.tags
}

resource "aws_route53_zone" "private_zone" {
  name = join(".", [var.stack_name, "vpc", var.hosted_zone_name])
  tags = var.tags

  vpc {
    vpc_id     = module.vpc.vpc_id
    vpc_region = var.aws_region
  }
}

resource "aws_route53_record" "public_zone" {
  zone_id = data.aws_route53_zone.hosted_zone.id
  type    = "NS"
  name    = aws_route53_zone.public_zone.name
  records = aws_route53_zone.public_zone.name_servers
  ttl     = 300
}