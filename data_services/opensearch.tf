resource "aws_security_group" "elasticsearch" {
  name = "${local.namespace}-elasticsearch"
  tags = local.tags
}

resource "aws_security_group_rule" "elasticsearch_egress" {
  security_group_id = aws_security_group.elasticsearch.id
  type              = "egress"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "elasticsearch_ingress" {
  security_group_id = aws_security_group.elasticsearch.id
  type              = "ingress"
  from_port         = "443"
  to_port           = "443"
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_opensearch_domain" "elasticsearch" {
  domain_name       = "${local.namespace}-index"
  engine_version    = "OpenSearch_2.13"
  tags              = local.tags

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
  }

  cluster_config {
    instance_type             = "m6g.large.search"
    instance_count            = var.opensearch_cluster_nodes
    zone_awareness_enabled    = true
    zone_awareness_config {
      availability_zone_count = min(var.opensearch_cluster_nodes, 3)
    }
  }

  ebs_options {
    ebs_enabled = "true"
    volume_size = var.opensearch_volume_size
  }


  lifecycle {
    ignore_changes = []
  }
}

resource "aws_opensearch_domain_policy" "elasticsearch" {
  domain_name     = aws_opensearch_domain.elasticsearch.domain_name
  access_policies = data.aws_iam_policy_document.elasticsearch_http_access.json
}

data "aws_caller_identity" "current_user" {}

data "aws_iam_policy_document" "elasticsearch_http_access" {
  statement {
    sid     = "allow-from-aws"
    effect  = "Allow"
    actions = ["es:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current_user.account_id}:root"]
    }
    resources = ["arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current_user.account_id}:domain/${local.namespace}-index/*"]
  }
}

# tflint-ignore: aws_resource_missing_tags
resource "aws_iam_service_linked_role" "elasticsearch" {
  aws_service_name = "es.amazonaws.com"
}

resource "aws_s3_bucket" "elasticsearch_snapshot_bucket" {
  bucket = "${local.namespace}-es-snapshots"
  tags   = local.tags
}

resource "aws_s3_bucket_acl" "elasticsearch_snapshot_bucket" {
  bucket = aws_s3_bucket.elasticsearch_snapshot_bucket.id
  acl    = "private"
}

resource "aws_iam_role" "elasticsearch_snapshot_bucket_access" {
  name               = "${local.namespace}-es-snapshot-role"
  assume_role_policy = data.aws_iam_policy_document.elasticsearch_snapshot_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "elasticsearch_snapshot_bucket_access" {
  name   = "${local.namespace}-es-snapshot-policy"
  role   = aws_iam_role.elasticsearch_snapshot_bucket_access.name
  policy = data.aws_iam_policy_document.elasticsearch_snapshot_bucket_access.json
}

data "aws_iam_policy_document" "elasticsearch_snapshot_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["es.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "elasticsearch_snapshot_bucket_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.elasticsearch_snapshot_bucket.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.elasticsearch_snapshot_bucket.arn}/*"]
  }
}

data "aws_iam_policy_document" "elasticsearch_read_access" {
  statement {
    effect  = "Allow"
    actions = ["es:ESHttpGet"]
    resources = [
      aws_opensearch_domain.elasticsearch.arn,
      "${aws_opensearch_domain.elasticsearch.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "elasticsearch_read_access" {
  name   = "${local.namespace}-elasticsearch-read"
  policy = data.aws_iam_policy_document.elasticsearch_read_access.json
  tags   = local.tags
}

data "aws_iam_policy_document" "elasticsearch_full_access" {
  statement {
    effect  = "Allow"
    actions = ["es:ESHttp*"]
    resources = [
      aws_opensearch_domain.elasticsearch.arn,
      "${aws_opensearch_domain.elasticsearch.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "elasticsearch_full_access" {
  name   = "${local.namespace}-elasticsearch-full"
  policy = data.aws_iam_policy_document.elasticsearch_full_access.json
  tags   = local.tags
}
