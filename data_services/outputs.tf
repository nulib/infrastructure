output "elasticsearch" {
  value = {
    arn             = aws_opensearch_domain.elasticsearch.arn
    domain_name     = aws_opensearch_domain.elasticsearch.domain_name
    endpoint        = "https://${aws_opensearch_domain.elasticsearch.endpoint}/"
    full_policy_arn = aws_iam_policy.elasticsearch_full_access.arn
    read_policy_arn = aws_iam_policy.elasticsearch_read_access.arn
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
