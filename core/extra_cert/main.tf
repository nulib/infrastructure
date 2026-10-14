resource "aws_acm_certificate" "this_cert" {
  domain_name                 = var.zone_name
  subject_alternative_names   = ["*.${var.zone_name}"]
  validation_method           = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "wildcard_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this_cert.domain_validation_options : dvo.domain_name => {
      type    = dvo.resource_record_type
      name    = dvo.resource_record_name
      value   = dvo.resource_record_value
      zone    = var.zone_id
    } if dvo.domain_name == var.zone_name
  }

  zone_id = each.value.zone
  type    = each.value.type
  name    = each.value.name
  records = [each.value.value]
  ttl     = 300
}

