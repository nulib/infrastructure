locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/staging-waf"
}
