module "aurora_postgresql" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 7.7"

  name                          = "${module.core.outputs.stack.namespace}-aurora-db-cluster"
  engine                        = "aurora-postgresql"
  engine_version                = var.aurora_engine_version
  engine_mode                   = "provisioned"
  vpc_id                        = module.core.outputs.vpc.id
  subnets                       = module.core.outputs.vpc.private_subnets.ids
  allowed_cidr_blocks           = [module.core.outputs.vpc.cidr_block, "10.0.0.0/16"]
  allow_major_version_upgrade   = true
  apply_immediately             = true
  create_db_parameter_group     = false
  create_security_group         = true
  enable_http_endpoint          = true
  preferred_backup_window       = "03:00-06:00"
  preferred_maintenance_window  = "Mon:00:00-Mon:03:00"

  master_username               = "postgres"
  create_random_password        = true

  tags                          = local.tags

  serverlessv2_scaling_configuration = {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  instance_class                = "db.serverless"
  instances = {
    one = {}
  }

  db_parameter_group_family     = "aurora-postgresql16"
  db_parameter_group_parameters = [ 
  ]

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
}

data "aws_iam_policy_document" "rds_assume_role" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]

    principals {
      type          = "Service"
      identifiers   = ["rds.amazonaws.com"]
    }
  }
}
