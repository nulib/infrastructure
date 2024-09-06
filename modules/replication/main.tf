terraform {
  required_providers {
    aws = {
      source                  = "hashicorp/aws"
      version                 = "~> 5.19"
      configuration_aliases   = [ aws.source, aws.target ]
    }
  }    
}

data "aws_region" "current" {
  provider = aws.target
}

locals {
  source_bucket_name = element(split(":", var.source_bucket_arn), 5)
}

resource "aws_iam_role" "this_role" {
  provider = aws.source

  # Only create the role in production env
  name  = "${local.source_bucket_name}-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "s3.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "${local.source_bucket_name}-replication-policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
          Resource = ["${var.source_bucket_arn}"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
          Resource = ["${var.source_bucket_arn}/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
          Resource = ["${aws_s3_bucket.this_replica.arn}/*"]
        }
      ]
    })
  }
}

resource "aws_s3_bucket" "this_replica" {
  provider = aws.target
  bucket   = "${local.source_bucket_name}-${data.aws_region.current.name}-replica"
}

resource "aws_s3_bucket_versioning" "this_replica" {
  provider = aws.target
  bucket   = aws_s3_bucket.this_replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "this" {
  provider    = aws.source
  role        = aws_iam_role.this_role.arn
  bucket      = local.source_bucket_name

  rule {
    id     = "preservation-replica"
    status = "Enabled"

    filter {
      prefix = ""
    }

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.this_replica.arn
      storage_class = "DEEP_ARCHIVE"
    }
  }

  lifecycle {
    ignore_changes = all
  }
}
