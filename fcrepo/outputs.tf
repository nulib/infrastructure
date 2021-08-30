output "endpoint" {
  value = "http://${aws_service_discovery_service.fcrepo.name}.${local.core.vpc.service_discovery_dns_zone.name}:8080/rest"
}