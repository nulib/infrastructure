locals {
  secrets = {
    db = {
      host     = aws_db_instance.db.address
      port     = aws_db_instance.db.port
      username = "dbadmin"
      password = random_string.db_master_password.result
    }

    index = {
      endpoint = aws_opensearch_domain.elasticsearch.endpoint
      models   = lookup(local.deploy_model_body, "model_id", "DEPLOY ERROR")
    }

    inference = {
      endpoints = {
        name     = var.embedding_model_name
        endpoint = "https://bedrock-runtime.${data.aws_region.current.name}.amazonaws.com/model/${var.embedding_model_name}/invoke"
      }
    }

    ldap = var.ldap_config
  }
}

resource "aws_secretsmanager_secret" "data_services" {
  for_each    = local.secrets
  name        = "${local.namespace}/infrastructure/${each.key}"
  description = "${each.key} secrets for ${local.namespace}"
}

resource "aws_secretsmanager_secret_version" "config_secrets" {
  for_each      = local.secrets
  secret_id     = aws_secretsmanager_secret.data_services[each.key].id
  secret_string = jsonencode(each.value)
}
