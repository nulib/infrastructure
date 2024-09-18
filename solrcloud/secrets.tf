locals {
  secrets = {
    solrcloud = {
      solr_url            = local.solr_endpoint
      zookeeper_servers   = local.zookeeper_servers
    }
  }
}

resource "aws_secretsmanager_secret" "data_services" {
  for_each    = local.secrets
  name        = "${local.prefix}/infrastructure/${each.key}"
  description = "${each.key} secrets for ${local.namespace}"
}

resource "aws_secretsmanager_secret_version" "config_secrets" {
  for_each      = local.secrets
  secret_id     = aws_secretsmanager_secret.data_services[each.key].id
  secret_string = jsonencode(each.value)
}
