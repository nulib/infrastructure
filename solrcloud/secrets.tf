locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/core"
  defaults  = jsonencode({
    zookeeper = {
      ensemble_size = 3
    }

    solr = {
      cluster_size  = 4
    }
  })
}
