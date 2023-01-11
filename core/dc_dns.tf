resource "aws_acm_certificate" "dc_wildcard" {
  count                       = length(aws_route53_zone.dc_zone)
  domain_name                 = "*.${aws_route53_zone.dc_zone[count.index].name}"
  subject_alternative_names   = [aws_route53_zone.dc_zone[count.index].name]
  validation_method           = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  validation_record = length(aws_route53_zone.dc_zone) == 0 ? {} : tolist(aws_acm_certificate.dc_wildcard[0].domain_validation_options)[0]
}

resource "aws_route53_record" "dc_wildcard_cert_validation" {
  count = length(aws_route53_zone.dc_zone)

  zone_id = aws_route53_zone.dc_zone[0].zone_id
  type    = local.validation_record.resource_record_type
  name    = local.validation_record.resource_record_name
  records = [local.validation_record.resource_record_value]
  ttl     = 300
}

resource "aws_route53_zone" "dc_zone" {
  count   = var.digital_collections_zone_name == "" ? 0 : 1
  name    = var.digital_collections_zone_name
  tags    = local.tags
}
