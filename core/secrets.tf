locals {
  secrets = {
    wildcard_cert = {
      domain            = aws_acm_certificate.wildcard_cert.domain_name
      certificate_arn   = aws_acm_certificate.wildcard_cert.arn
    }
  }
}

resource "aws_secretsmanager_secret" "data_services" {
  for_each    = local.secrets
  name        = "${terraform.workspace}/infrastructure/${each.key}"
  description = "${each.key} secrets for ${terraform.workspace}"
}

resource "aws_secretsmanager_secret_version" "config_secrets" {
  for_each      = local.secrets
  secret_id     = aws_secretsmanager_secret.data_services[each.key].id
  secret_string = jsonencode(each.value)
}
