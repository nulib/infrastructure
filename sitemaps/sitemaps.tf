data "aws_route53_zone" "sitemap_zone" {
  name = var.zone_name
}

resource "aws_s3_bucket" "sitemap_bucket" {
  bucket = var.hostname
}

resource "aws_cloudfront_origin_access_identity" "sitemap_access" {
  comment = "CloudFront access to ${var.hostname}"
}

data "aws_iam_policy_document" "allow_sitemap_bucket_access_from_cloudfront" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.sitemap_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.sitemap_access.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "sitemap_bucket" {
  bucket = aws_s3_bucket.sitemap_bucket.id
  policy = data.aws_iam_policy_document.allow_sitemap_bucket_access_from_cloudfront.json
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "cors_s3_origin" {
  name = "Managed-CORS-S3Origin"
}

data "aws_cloudfront_response_headers_policy" "simple_cors" {
  name = "Managed-SimpleCORS"
}

data "aws_acm_certificate" "domain_certificate" {
  domain = var.certificate_domain
}

resource "aws_cloudfront_distribution" "sitemaps" {
  aliases       = [var.hostname]
  price_class   = "PriceClass_100"
  enabled       = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.domain_certificate.arn
    ssl_support_method  = "sni-only"
  }

  origin {
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.sitemap_access.cloudfront_access_identity_path
    }
    origin_id     = "sitemaps"
    domain_name   = aws_s3_bucket.sitemap_bucket.bucket_regional_domain_name
    origin_path   = "/priv/static"
  }

  default_cache_behavior {
    allowed_methods             = ["HEAD", "GET", "OPTIONS"]
    cached_methods              = ["HEAD", "GET"]
    cache_policy_id             = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id    = data.aws_cloudfront_origin_request_policy.cors_s3_origin.id
    response_headers_policy_id  = data.aws_cloudfront_response_headers_policy.simple_cors.id
    target_origin_id            = "sitemaps"
    viewer_protocol_policy      = "allow-all"
  }
}

resource "aws_route53_record" "sitemap_record" {
  zone_id   = data.aws_route53_zone.sitemap_zone.id
  name      = var.hostname
  type      = "A"

  alias {
    name                      = aws_cloudfront_distribution.sitemaps.domain_name
    zone_id                   = aws_cloudfront_distribution.sitemaps.hosted_zone_id
    evaluate_target_health    = false
  }
}