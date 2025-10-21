locals {
  secrets = {
    aurora = {
      host        = module.aurora_postgresql.cluster_endpoint
      port        = module.aurora_postgresql.cluster_port
      username    = module.aurora_postgresql.cluster_master_username
      password    = module.aurora_postgresql.cluster_master_password
    }

    db = {
      host     = aws_db_instance.db.address
      port     = aws_db_instance.db.port
      username = "dbadmin"
      password = random_string.db_master_password.result
    }

    cache = {
      address   = aws_route53_record.redis.name
      port      = 6379
    }

    index = {
      endpoint             = "https://${aws_opensearch_domain.elasticsearch.endpoint}"
      embedding_model      = lookup(local.deploy_model_body, "model_id", "DEPLOY ERROR")
      embedding_dimensions = var.embedding_dimensions
    }

    inference = {
      name       = var.embedding_model_name
      endpoint   = "https://bedrock-runtime.${data.aws_region.current.region}.amazonaws.com/model/${var.embedding_model_name}/invoke"
      dimensions = var.embedding_dimensions
    }

    ldap = merge(var.ldap_config, { port = tonumber(var.ldap_config["port"]) })
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
