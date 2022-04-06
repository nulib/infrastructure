module "vpc" {
  source    = "terraform-aws-modules/vpc/aws"
  version   = "3.7.0"

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

resource "aws_security_group" "internal_http" {
  name        = "${local.namespace}-exhibitor-lb"
  description = "Local VPC HTTP Security Group"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.cidr_block]
  }

  tags = local.tags
}

module "endpoints" {
  source    = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version   = "3.7.0"

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
    }
  }

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}