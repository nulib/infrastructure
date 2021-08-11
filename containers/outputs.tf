output "registry_url" {
  value = "${data.aws_caller_identity.current.id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}