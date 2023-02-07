terraform {
  backend "s3" {
    key    = "switchboard.tfstate"
  }

  required_providers {
    aws = "~> 4.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  default_tags {
    tags = {
      Department  = "RDC"
      Environment = terraform.workspace
      Terraform   = "true"
      Component   = "switchboard",
      Git         = "github.com/nulib/infrastructure"
      Project     = "Infrastructure"
    }
  }
}

locals {
  function_source = templatefile("${path.module}/src/index.js", {
    mappings          = jsonencode(local.mappings)
    response_status   = jsonencode(var.response_status)
  })

  dns_names = {
    for k, v in var.mappings: v.dns => trimprefix(v.dns, regex("^.+?\\.", v.dns))
  }

  mappings = {
    for k, v in var.mappings: k => v.target
  }

  zones = {
    for k, v in var.mappings: k => trimprefix(k, regex("^.+?\\.", k))
  }

  dvo_records = var.certificate_arn == "" ? {
    for dvo in aws_acm_certificate.switchboard_cert[0].domain_validation_options : dvo.domain_name => {
      type    = dvo.resource_record_type
      name    = dvo.resource_record_name
      value   = dvo.resource_record_value
      zone    = data.aws_route53_zone.mapping_zones[dvo.domain_name].zone_id
    }
  } : {}
}

resource "aws_acm_certificate" "switchboard_cert" {
  count                       = var.certificate_arn == "" ? 1 : 0
  domain_name                 = keys(local.zones)[0]
  subject_alternative_names   = slice(keys(local.zones), 1, length(keys(local.zones)))
  validation_method           = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "switchboard_cert_validation" {
  for_each = local.dvo_records

  zone_id = each.value.zone
  type    = each.value.type
  name    = each.value.name
  records = [each.value.value]
  ttl     = 300
}

resource "aws_cloudfront_function" "switchboard" {
  name    = "switchboard-mapper"
  code    = local.function_source
  runtime = "cloudfront-js-1.0"
  publish = true
}

data "aws_cloudfront_cache_policy" "no_caching" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "switchboard" {
  aliases       = toset(keys(var.mappings))
  price_class   = "PriceClass_100"
  enabled       = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.certificate_arn == "" ? aws_acm_certificate.switchboard_cert[0].arn : var.certificate_arn
    ssl_support_method  = "sni-only"
  }

  origin {
    custom_origin_config {
      http_port                 = 80
      https_port                = 443
      origin_protocol_policy    = "https-only"
      origin_ssl_protocols      = ["TLSv1.2"]
    }
    origin_id     = "nothing"
    domain_name   = "dev.null"
  }

  default_cache_behavior {
    allowed_methods           = ["HEAD", "GET", "OPTIONS"]
    cached_methods            = ["HEAD", "GET"]
    cache_policy_id           = data.aws_cloudfront_cache_policy.no_caching.id
    target_origin_id          = "nothing" 
    viewer_protocol_policy    = "allow-all"

    function_association {
      event_type    = "viewer-request"
      function_arn  = aws_cloudfront_function.switchboard.arn
    }
  }
}

data "aws_route53_zone" "mapping_zones" {
  for_each    = local.dns_names
  name        = each.value
}

resource "aws_route53_record" "switchboard" {
  for_each    = local.dns_names
  zone_id     = data.aws_route53_zone.mapping_zones[each.key].zone_id
  name        = each.key
  type        = "A"

  alias {
    name                      = aws_cloudfront_distribution.switchboard.domain_name
    zone_id                   = aws_cloudfront_distribution.switchboard.hosted_zone_id
    evaluate_target_health    = false
  }
}
