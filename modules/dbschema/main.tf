data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/core.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "env:/${terraform.workspace}/db.tfstate"
    region = var.aws_region
  }
}

locals {
  core = data.terraform_remote_state.core.outputs
  db   = data.terraform_remote_state.db.outputs
}

resource "random_string" "role_password" {
  length  = 16
  upper   = true
  lower   = true
  number  = true
  special = false
}

locals {
  create_script = <<EOF
DO
\$do\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${var.schema}') THEN
    CREATE ROLE ${var.schema};
  END IF;
  ALTER ROLE ${var.schema} WITH LOGIN ENCRYPTED PASSWORD '${random_string.role_password.result}';
  IF NOT EXISTS (
    SELECT FROM pg_catalog.pg_auth_members a
      JOIN pg_catalog.pg_roles b ON a.roleid = b.oid
      JOIN pg_catalog.pg_roles c ON a.member = c.oid
      WHERE c.rolname = '${local.db.admin_user}' AND b.rolname = '${var.schema}'
  ) THEN
    GRANT ${var.schema} TO ${local.db.admin_user};
  END IF;
END
\$do\$;
CREATE DATABASE ${var.schema} OWNER ${var.schema};
EOF

  psql            = "PGPASSWORD='${local.db.admin_password}' psql -U ${local.db.admin_user} -h ${local.db.address} -p ${local.db.port} postgres"
  create_command  = "echo \"${local.create_script}\" | ${local.psql}"
}

resource "null_resource" "this_database" {
  triggers = {
    value = local.db.address
  }

  connection {
    user        = "ec2-user"
    host        = local.core.bastion.hostname
    agent       = true
    timeout     = "3m"
  }

  provisioner "remote-exec" {
    inline = ["${local.create_command}"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
