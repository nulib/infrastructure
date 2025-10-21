resource "random_string" "aurora_master_password" {
  length  = 10
  upper   = true
  lower   = true
  numeric = true
  special = false

  lifecycle {
    ignore_changes = all
  }
}

module "aurora_postgresql" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.16"

  name                                = "${module.core.outputs.stack.namespace}-aurora-db-cluster"
  engine                              = "aurora-postgresql"
  engine_version                      = var.aurora_engine_version
  engine_mode                         = "provisioned"
  vpc_id                              = module.core.outputs.vpc.id
  subnets                             = module.core.outputs.vpc.private_subnets.ids
  allow_major_version_upgrade         = true
  apply_immediately                   = true
  create_db_cluster_parameter_group   = true
  create_db_parameter_group           = true
  create_security_group               = true
  enable_http_endpoint                = true
  preferred_backup_window             = "03:00-06:00"
  preferred_maintenance_window        = "Mon:00:00-Mon:03:00"

  master_username                     = "postgres"
  master_password                     = random_string.aurora_master_password.result
  manage_master_user_password         = false

  tags                          = local.tags

  security_group_rules = {
    vpc_ingress = {
      cidr_blocks       = [module.core.outputs.vpc.cidr_block, "10.0.0.0/16"]
    }
  }

  serverlessv2_scaling_configuration = {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  instance_class                = "db.serverless"
  instances = {
    one = {}
  }

  db_cluster_parameter_group_family     = "aurora-postgresql16"
  db_cluster_parameter_group_parameters = [
    {
      name            = "rds.logical_replication"
      value           = 1
      apply_method    = "pending-reboot"
    },
  ]

  db_parameter_group_family     = "aurora-postgresql16"
  db_parameter_group_parameters = [
    {
      name            = "max_locks_per_transaction"
      value           = 1024
      apply_method    = "pending-reboot"
    }
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

module "user_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.1.1"

  function_name          = "${local.namespace}-db-user"
  description            = "Creates and manages database users"
  handler                = "main.handler"
  runtime                = "python3.12"
  source_path            = "${path.module}/db_user_lambda"
  timeout                = 600
  publish                = true

  vpc_subnet_ids         = module.core.outputs.vpc.public_subnets.ids
  vpc_security_group_ids = [aws_security_group.db_client.id]
  attach_network_policy  = true

  environment_variables = {
    DB_HOST                 = module.aurora_postgresql.cluster_endpoint
    DB_PORT                 = module.aurora_postgresql.cluster_port
    DB_SUPERUSER            = module.aurora_postgresql.cluster_master_username
    DB_SUPERUSER_PASSWORD   = module.aurora_postgresql.cluster_master_password
  }

  assume_role_policy_statements = {
    admin = {
      effect = "Allow"
      actions = ["sts:AssumeRole"]
      principals = {
        admin_principal = {
          type        = "AWS"
          identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
      }

      condition = {
        admin_role_condition = {
          test     = "StringLike"
          variable = "aws:PrincipalArn"
          values   = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_AWSAdministratorAccess_*"]
        }
      }
    }
  }
}
