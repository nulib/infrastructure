output "fedora4_endpoint" {
  value = "http://${aws_service_discovery_service.fcrepo.name}.${module.core.outputs.vpc.service_discovery_dns_zone.name}:8080/rest"
}

output "fedora6_endpoint" {
  value = "http://${aws_service_discovery_service.fedora6.name}.${module.core.outputs.vpc.service_discovery_dns_zone.name}:8080/rest"
}

output "fedora6_ocfl_bucket" {
  value = aws_s3_bucket.fedora6_ocfl_bucket.id
}