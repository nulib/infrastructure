locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/core"
  defaults  = jsonencode({
    zookeeper = {
      ensemble_size = 3
      cpu           = 256
      memory        = 512
    }

    solr = {
      cluster_size  = 4
      cpu           = 1024
      memory        = 2048
    }
  })
}
