resource "aws_sesv2_email_identity" "domain_email" {
  email_identity = aws_route53_zone.hosted_zone.name
  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

resource "aws_sesv2_email_identity_mail_from_attributes" "domain_email" {
  email_identity = aws_sesv2_email_identity.domain_email.email_identity

  behavior_on_mx_failure = "REJECT_MESSAGE"
  mail_from_domain       = "mail.${aws_sesv2_email_identity.domain_email.email_identity}"
}

resource "aws_route53_record" "domain_email" {
  for_each = toset(aws_sesv2_email_identity.domain_email.dkim_signing_attributes[0].tokens)
  zone_id  = aws_route53_zone.hosted_zone.zone_id
  name     = "${each.key}._domainkey.${aws_sesv2_email_identity.domain_email.email_identity}"
  type     = "CNAME"
  ttl      = 300
  records  = ["${each.key}.dkim.amazonses.com"]
}

resource "aws_route53_record" "dmarc_mx" {
  zone_id  = aws_route53_zone.hosted_zone.zone_id
  name     = "mail.${aws_sesv2_email_identity.domain_email.email_identity}"
  type     = "MX"
  ttl      = 300
  records  = ["10 feedback-smtp.${data.aws_region.current.name}.amazonses.com"]
}

resource "aws_route53_record" "dmarc_txt" {
  zone_id  = aws_route53_zone.hosted_zone.zone_id
  name     = "mail.${aws_sesv2_email_identity.domain_email.email_identity}"
  type     = "TXT"
  ttl      = 300
  records  = ["v=spf1 include:amazonses.com ~all"]
}
