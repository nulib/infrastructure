resource "aws_acm_certificate" "dc_wildcard" {
  count                       = length(aws_route53_zone.dc_zone)
  domain_name                 = "*.${aws_route53_zone.dc_zone[count.index].name}"
  subject_alternative_names   = [aws_route53_zone.dc_zone[count.index].name]
  validation_method           = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "dc_wildcard_cert_validation" {
  for_each = length(aws_route53_zone.dc_zone) == 0 ? {} : {
    for dvo in aws_acm_certificate.dc_wildcard[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.dc_zone[0].zone_id
  type    = each.value.type
  name    = each.value.name
  records = [each.value.record]
  ttl     = 300
}

resource "aws_route53_zone" "dc_zone" {
  count   = var.digital_collections_zone_name == "" ? 0 : 1
  name    = var.digital_collections_zone_name
  tags    = local.tags
}

resource "aws_route53_record" "dc_cname" {
  zone_id = aws_route53_zone.dc_zone[0].zone_id
  name    = "."
  type    = "CNAME"
  records = ["dc.stack.rdc.library.northwestern.edu"]
  ttl     = 60
}
