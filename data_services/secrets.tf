locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/data_services"
  defaults  = jsonencode({
    postgres_version    = "13.3"
    allocated_storage   = 100
    instance_class      = "db.t3.medium"
  })
}
