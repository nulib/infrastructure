locals {
  deploy_model_result   = { for key in keys(var.sagemaker_configurations) : key => jsondecode(aws_lambda_invocation.deploy_model[key].result) }
  deploy_model_body     = { for key in keys(var.sagemaker_configurations) : key => jsondecode(local.deploy_model_result[key].body) }
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
  value = { for key, value in local.deploy_model_body : key => {    
    endpoint_name         = aws_sagemaker_endpoint.serverless_inference[key].name
    invocation_url        = local.embedding_invocation_url[key]
    opensearch_model_id   = lookup(value, "model_id", "DEPLOY ERROR")
  }}
}

output "search_snapshot_configuration" {
  value = {
    create_url    = "https://${aws_opensearch_domain.elasticsearch.endpoint}/_snapshot/"
    create_doc    = jsonencode({
      type     = "s3"
      settings = {
        bucket    = aws_s3_bucket.elasticsearch_snapshot_bucket.id
        region    = data.aws_region.current.name
        role_arn  = aws_iam_role.elasticsearch_snapshot_bucket_access.arn
      }
    })
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
  }
}

output "redis" {
  value = {
    address               = aws_route53_record.redis.name
    port                  = 6379
    client_security_group = aws_security_group.redis_client.id
  }
}
