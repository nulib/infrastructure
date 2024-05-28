locals {
  secrets = {
    db = {
      host        = aws_db_instance.db.address
      port        = aws_db_instance.db.port
      username    = "dbadmin"
      password    = random_string.db_master_password.result
    }

    index = {
      endpoint    = aws_opensearch_domain.elasticsearch.endpoint
      models      = { for key, value in local.deploy_model_body : key => lookup(value, "model_id", "DEPLOY ERROR") }
    }

    inference = {
      endpoints = { for key, value in local.deploy_model_body : key => {    
        name        = aws_sagemaker_endpoint.serverless_inference[key].name
        endpoint    = local.embedding_invocation_url[key]
      }}
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
