locals {
  deploy_model_result = jsondecode(aws_lambda_invocation.deploy_model.result)
  deploy_model_body   = jsondecode(local.deploy_model_result.body)
}

output "elasticsearch" {
  value = {
    arn             = aws_opensearch_domain.elasticsearch.arn
    domain_name     = aws_opensearch_domain.elasticsearch.domain_name
    endpoint        = "https://${aws_opensearch_domain.elasticsearch.endpoint}/"
    full_policy_arn = aws_iam_policy.elasticsearch_full_access.arn
    read_policy_arn = aws_iam_policy.elasticsearch_read_access.arn
  }
}

output "inference" {
  value = {
    endpoint_name       = var.embedding_model_name
    invocation_url      = "https://bedrock-runtime.${data.aws_region.current.region}.amazonaws.com/model/${var.embedding_model_name}/invoke"
    opensearch_model_id = lookup(local.deploy_model_body, "model_id", "DEPLOY ERROR")
  }
}

output "search_snapshot_configuration" {
  value = {
    create_url = "https://${aws_opensearch_domain.elasticsearch.endpoint}/_snapshot/"
    create_doc = jsonencode({
      type = "s3"
      settings = {
        bucket   = aws_s3_bucket.elasticsearch_snapshot_bucket.id
        region   = data.aws_region.current.region
        role_arn = aws_iam_role.elasticsearch_snapshot_bucket_access.arn
      }
    })
  }
}

output "aurora" {
  sensitive = true
  value = {
    cluster_name    = module.aurora_postgresql.cluster_id
    endpoint        = module.aurora_postgresql.cluster_endpoint
    port            = module.aurora_postgresql.cluster_port
    admin_user      = module.aurora_postgresql.cluster_master_username
    admin_password  = module.aurora_postgresql.cluster_master_password
    user_lambda     = module.user_lambda.lambda_function_arn
  }
}

output "postgres" {
  value = {
    address               = aws_db_instance.db.address
    port                  = aws_db_instance.db.port
    instance_name         = aws_db_instance.db.id
    client_security_group = aws_security_group.db_client.id
    admin_user            = "dbadmin"
    admin_password        = random_string.db_master_password.result
    maintenance_lambda    = module.maintenance_lambda.lambda_function_arn
  }
}

output "redis" {
  value = {
    address               = aws_route53_record.redis.name
    port                  = 6379
    client_security_group = aws_security_group.redis_client.id
  }
}
