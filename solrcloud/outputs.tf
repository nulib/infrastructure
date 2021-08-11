output "solr_endpoint" {
  value = "http://${aws_service_discovery_service.solr.name}.${local.vpc.service_discovery_dns_zone.name}:8983/solr/"
}

output "zookeeper_servers" {
  value = local.zookeeper_servers
}