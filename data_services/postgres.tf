resource "random_string" "db_master_password" {
  length  = 16
  upper   = true
  lower   = true
  numeric = true
  special = false
}

resource "aws_security_group" "db" {
  name          = "${local.namespace}-db"
  description   = "RDS Security Group"
  vpc_id        = module.core.outputs.vpc.id
  tags          = local.tags
}

resource "aws_security_group_rule" "db_egress" {
  type                = "egress"
  security_group_id   = aws_security_group.db.id
  from_port           = 0
  to_port             = 65535
  protocol            = -1
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "db_ingress" {
  type                        = "ingress"
  security_group_id           = aws_security_group.db.id
  from_port                   = aws_db_instance.db.port
  to_port                     = aws_db_instance.db.port
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.db_client.id
}

resource "aws_security_group" "db_client" {
  name          = "${local.namespace}-db-client"
  description   = "RDS Client Security Group"
  vpc_id        = module.core.outputs.vpc.id

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags          = local.tags
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name_prefix   = "${local.namespace}-db-"
  subnet_ids    = module.core.outputs.vpc.private_subnets.ids
  tags          = local.tags

  lifecycle {
    create_before_destroy   = true
    ignore_changes          = [description]
  }
}

resource "aws_db_parameter_group" "db_parameter_group" {
  name_prefix   = "${local.namespace}-db-"
  family        = "postgres${element(split(".", var.postgres_version), 0)}"
  tags          = local.tags
  
  parameter {
    name = "client_encoding"
    value = "UTF8"
    apply_method = "pending-reboot"
  }

  parameter {
    name = "max_locks_per_transaction"
    value = 256
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "db" {
  allocated_storage         = 125
  apply_immediately         = true
  engine                    = "postgres"
  engine_version            = var.postgres_version
  instance_class            = var.instance_class
  db_name                   = "${module.core.outputs.stack.name}db"
  username                  = "dbadmin"
  parameter_group_name      = aws_db_parameter_group.db_parameter_group.name
  password                  = random_string.db_master_password.result
  maintenance_window        = "Mon:00:00-Mon:03:00"
  backup_window             = "03:00-06:00"
  backup_retention_period   = 35
  copy_tags_to_snapshot     = true
  db_subnet_group_name      = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.db.id]
  tags                      = local.tags

  lifecycle {
    ignore_changes = [ engine_version, maintenance_window ]
  }
}

module "maintenance_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 3.3.1"

  function_name          = "${local.namespace}-db-maintenance"
  description            = "Cleans and vacuums certain database tables"
  handler                = "main.handler"
  runtime                = "python3.12"
  source_path            = "${path.module}/db_maintenance"
  timeout                = 600
  publish                = true

  vpc_subnet_ids         = module.core.outputs.vpc.public_subnets.ids
  vpc_security_group_ids = [aws_security_group.db_client.id]
  attach_network_policy  = true

  allowed_triggers = {
    DBMaintenanceRule = {

      principal  = "events.amazonaws.com"
    }
  }
}
