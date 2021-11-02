locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/firewall"
  defaults  = jsonencode({
    resources    = {}
  })
}
