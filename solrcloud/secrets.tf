locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "../modules/secrets"
  path      = "infrastructure/core"
  defaults  = jsonencode({
    zookeeper_ensemble_size   = 3
    solr_cluster_size         = 4
  })
}
