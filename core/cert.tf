locals {
  all_zones = flatten([aws_route53_zone.hosted_zone.name, aws_route53_zone.public_zone.name, var.additional_environment_zones])

  certificate_sans = flatten([
    local.all_zones,
    [for zone in local.all_zones : "*.${zone}"]
  ])
}

data "aws_route53_zone" "environment_zones" {
  for_each    = toset(local.all_zones)
  name        = each.key
}

resource "aws_acm_certificate" "wildcard_cert" {
  domain_name                 = aws_route53_zone.hosted_zone.name
  subject_alternative_names   = local.certificate_sans
  validation_method           = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "wildcard_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard_cert.domain_validation_options : dvo.domain_name => {
      type    = dvo.resource_record_type
      name    = dvo.resource_record_name
      value   = dvo.resource_record_value
      zone    = data.aws_route53_zone.environment_zones[dvo.domain_name].zone_id
    } if contains(local.all_zones, dvo.domain_name)
  }

  zone_id = each.value.zone
  type    = each.value.type
  name    = each.value.name
  records = [each.value.value]
  ttl     = 300
}
