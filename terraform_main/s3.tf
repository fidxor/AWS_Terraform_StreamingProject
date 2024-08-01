provider "aws" {
  region = "ap-northeast-2"
}

resource "aws_s3_bucket" "nonoinput" {
  bucket = "nonoinput"
}

resource "aws_s3_bucket" "nonooutput" {
  bucket = "nonooutput"
}

locals {
  common_bucket_config = {
    object_ownership        = "BucketOwnerEnforced"
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
    versioning_enabled      = true
    sse_algorithm           = "AES256"
    bucket_key_enabled      = true
  }
}

resource "aws_s3_bucket_ownership_controls" "main_buckets_ownership" {
  for_each = {
    nonoinput  = aws_s3_bucket.nonoinput.id
    nonooutput = aws_s3_bucket.nonooutput.id
  }
  bucket = each.value

  rule {
    object_ownership = local.common_bucket_config.object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "main_buckets_public_access" {
  for_each = {
    nonoinput  = aws_s3_bucket.nonoinput.id
    nonooutput = aws_s3_bucket.nonooutput.id
  }
  bucket = each.value

  block_public_acls       = local.common_bucket_config.block_public_acls
  block_public_policy     = local.common_bucket_config.block_public_policy
  ignore_public_acls      = local.common_bucket_config.ignore_public_acls
  restrict_public_buckets = local.common_bucket_config.restrict_public_buckets
}

resource "aws_s3_bucket_versioning" "main_buckets_versioning" {
  for_each = {
    nonoinput  = aws_s3_bucket.nonoinput.id
    nonooutput = aws_s3_bucket.nonooutput.id
  }
  bucket = each.value

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main_buckets_encryption" {
  for_each = {
    nonoinput  = aws_s3_bucket.nonoinput.id
    nonooutput = aws_s3_bucket.nonooutput.id
  }
  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = local.common_bucket_config.sse_algorithm
    }
    bucket_key_enabled = local.common_bucket_config.bucket_key_enabled
  }
}

resource "aws_s3_bucket_cors_configuration" "bucket_cors" {
  for_each = {
    nonoinput  = aws_s3_bucket.nonoinput
    nonooutput = aws_s3_bucket.nonooutput
  }
  
  bucket = each.value.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

data "aws_cloudfront_origin_access_identity" "nono_oai" {
  id = aws_cloudfront_origin_access_identity.nono_oai.id
}

locals {
  s3_origin_id = "nonooutput-origin"
  cloudfront_oai_iam_arn = data.aws_cloudfront_origin_access_identity.nono_oai.iam_arn

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          AWS = local.cloudfront_oai_iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "%s/*"
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "cloudfront_access_policy" {
  bucket = aws_s3_bucket.nonooutput.id
  policy = format(local.bucket_policy, aws_s3_bucket.nonooutput.arn)
}