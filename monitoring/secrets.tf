locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/monitoring"
  defaults  = jsonencode({
    actions_enabled   = false
    alarm_actions     = []
    load_balancers    = []
    services          = []
  })
}
