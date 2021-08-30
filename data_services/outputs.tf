output "elasticsearch" {
  value = {
    arn      = aws_elasticsearch_domain.elasticsearch.arn
    endpoint = "https://${aws_elasticsearch_domain.elasticsearch.endpoint}/"
  }
}

output "postgres" {
  value = {
    address                 = aws_db_instance.db.address
    port                    = aws_db_instance.db.port
    client_security_group   = aws_security_group.db_client.id
    admin_user              = "dbadmin"
    admin_password          = random_string.db_master_password.result
  }
}

output "redis" {
  value = {
    address                 = aws_route53_record.redis.name
    port                    = 6379
    client_security_group   = aws_security_group.redis_client.id
  }
}