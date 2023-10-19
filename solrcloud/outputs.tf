locals {
  solr_endpoint = "http://${aws_service_discovery_service.solr.name}.${module.core.outputs.vpc.service_discovery_dns_zone.name}:8983/solr"
}

output "utils" {
  value = {
    function_arn            = module.backup_lambda.lambda_function_arn
    qualified_function_arn  = module.backup_lambda.lambda_function_qualified_arn
  }
}
output "solr" {
  value = {
    endpoint                = local.solr_endpoint
    client_security_group   = aws_security_group.solr_client.id
    cluster_size            = var.solr_cluster_size
  }
}

output "zookeeper" {
  value = {
    servers                 = local.zookeeper_servers
    client_security_group   = aws_security_group.zookeeper_client.id
  }
}