terraform {
  backend "s3" {
    key    = "vpc.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  environment   = coalesce(var.environment, substr(terraform.workspace, 0, 1))
  namespace     = join("-", [var.stack_name, local.environment])
  tags          = merge(var.tags, {Component = "vpc"})
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.namespace}-vpc"
  cidr = var.cidr_block

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  single_nat_gateway   = true

  create_database_subnet_group = false

  private_subnet_tags = {
    SubnetType = "private"
  }

  public_subnet_tags = {
    SubnetType = "public"
  }

  tags = local.tags
}

resource "aws_security_group" "endpoint_access" {
  name        = "${local.namespace}-endpoints"
  description = "VPC Endpoint Security Group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.cidr_block]
  }

  tags = local.tags
}

module "endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc.default_security_group_id, aws_security_group.endpoint_access.id]
  endpoints = {
    s3 = {
      # interface endpoint
      service             = "s3"
      subnet_ids          = module.vpc.private_subnets
      tags                = local.tags
    },
    ssm = {
      service             = "ssm"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = local.tags
    },
    ssmmessages = {
      service             = "ssmmessages"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = local.tags
    },
    ec2 = {
      service             = "ec2"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = local.tags
    },
    sqs = {
      service             = "sqs"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = local.tags
    },
  }

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

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