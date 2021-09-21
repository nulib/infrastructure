output "solr" {
  value = {
    endpoint                = "http://${aws_service_discovery_service.solr.name}.${module.core.outputs.vpc.service_discovery_dns_zone.name}:8983/solr"
    client_security_group   = aws_security_group.solr_client.id
    cluster_size            = local.secrets.solr_cluster_size
  }
}

output "zookeeper" {
  value = {
    servers                 = local.zookeeper_servers
    client_security_group   = aws_security_group.zookeeper_client.id
  }
}