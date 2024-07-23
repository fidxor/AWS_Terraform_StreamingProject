provider "aws" {
  region = "ap-northeast-2"  # 기본 리전
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "ca-central-1"
  region = "ca-central-1"
}

resource "aws_s3_bucket" "nonoinput" {
  bucket = "nonoinput"
}

resource "aws_s3_bucket" "nonooutput" {
  bucket = "nonooutput"
}

# 공통 S3 버킷 설정
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

# nonoinput과 nonooutput 버킷 설정
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

# 다른 리전의 버킷 생성
resource "aws_s3_bucket" "nonooutput_ap_northeast_2" {
  bucket = "nonooutput-ap-northeast-2"
}

resource "aws_s3_bucket" "nonooutput_ca_central_1" {
  provider = aws.ca-central-1
  bucket   = "nonooutput-ca-central-1"
}

resource "aws_s3_bucket" "nonooutput_us_east_1" {
  provider = aws.us-east-1
  bucket   = "nonooutput-us-east-1"
}

# 리전별 버킷 설정
# ap-northeast-2
resource "aws_s3_bucket_ownership_controls" "ap_northeast_2_ownership" {
  bucket = aws_s3_bucket.nonooutput_ap_northeast_2.id
  rule {
    object_ownership = local.common_bucket_config.object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "ap_northeast_2_public_access" {
  bucket = aws_s3_bucket.nonooutput_ap_northeast_2.id
  block_public_acls       = local.common_bucket_config.block_public_acls
  block_public_policy     = local.common_bucket_config.block_public_policy
  ignore_public_acls      = local.common_bucket_config.ignore_public_acls
  restrict_public_buckets = local.common_bucket_config.restrict_public_buckets
}

resource "aws_s3_bucket_versioning" "ap_northeast_2_versioning" {
  bucket = aws_s3_bucket.nonooutput_ap_northeast_2.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ap_northeast_2_encryption" {
  bucket = aws_s3_bucket.nonooutput_ap_northeast_2.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = local.common_bucket_config.sse_algorithm
    }
    bucket_key_enabled = local.common_bucket_config.bucket_key_enabled
  }
}

# ca-central-1
resource "aws_s3_bucket_ownership_controls" "ca_central_1_ownership" {
  provider = aws.ca-central-1
  bucket = aws_s3_bucket.nonooutput_ca_central_1.id
  rule {
    object_ownership = local.common_bucket_config.object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "ca_central_1_public_access" {
  provider = aws.ca-central-1
  bucket = aws_s3_bucket.nonooutput_ca_central_1.id
  block_public_acls       = local.common_bucket_config.block_public_acls
  block_public_policy     = local.common_bucket_config.block_public_policy
  ignore_public_acls      = local.common_bucket_config.ignore_public_acls
  restrict_public_buckets = local.common_bucket_config.restrict_public_buckets
}

resource "aws_s3_bucket_versioning" "ca_central_1_versioning" {
  provider = aws.ca-central-1
  bucket = aws_s3_bucket.nonooutput_ca_central_1.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ca_central_1_encryption" {
  provider = aws.ca-central-1
  bucket = aws_s3_bucket.nonooutput_ca_central_1.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = local.common_bucket_config.sse_algorithm
    }
    bucket_key_enabled = local.common_bucket_config.bucket_key_enabled
  }
}

# us-east-1
resource "aws_s3_bucket_ownership_controls" "us_east_1_ownership" {
  provider = aws.us-east-1
  bucket = aws_s3_bucket.nonooutput_us_east_1.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "us_east_1_public_access" {
  provider = aws.us-east-1
  bucket = aws_s3_bucket.nonooutput_us_east_1.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_versioning" "us_east_1_versioning" {
  provider = aws.us-east-1
  bucket = aws_s3_bucket.nonooutput_us_east_1.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "us_east_1_encryption" {
  provider = aws.us-east-1
  bucket = aws_s3_bucket.nonooutput_us_east_1.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# CORS 설정
resource "aws_s3_bucket_cors_configuration" "bucket_cors" {
  for_each = {
    nonoinput                 = aws_s3_bucket.nonoinput
    nonooutput                = aws_s3_bucket.nonooutput
    nonooutput-ap-northeast-2 = aws_s3_bucket.nonooutput_ap_northeast_2
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

resource "aws_s3_bucket_cors_configuration" "bucket_cors_ca_central_1" {
  provider = aws.ca-central-1
  bucket   = aws_s3_bucket.nonooutput_ca_central_1.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_cors_configuration" "bucket_cors_us_east_1" {
  provider = aws.us-east-1
  bucket   = aws_s3_bucket.nonooutput_us_east_1.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

# CloudFront OAI
data "aws_cloudfront_origin_access_identity" "nono_oai" {
  id = aws_cloudfront_origin_access_identity.nono_oai.id
}

# 버킷 정책 함수
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

# 버킷 정책 적용
resource "aws_s3_bucket_policy" "cloudfront_access_policy" {
  for_each = {
    nonooutput                = aws_s3_bucket.nonooutput.arn
    nonooutput-ap-northeast-2 = aws_s3_bucket.nonooutput_ap_northeast_2.arn
  }
  
  bucket = each.key
  policy = format(local.bucket_policy, each.value)
}

resource "aws_s3_bucket_policy" "cloudfront_access_policy_ca_central_1" {
  provider = aws.ca-central-1
  bucket   = aws_s3_bucket.nonooutput_ca_central_1.id
  policy   = format(local.bucket_policy, aws_s3_bucket.nonooutput_ca_central_1.arn)
}

resource "aws_s3_bucket_policy" "cloudfront_access_policy_us_east_1" {
  provider = aws.us-east-1
  bucket   = aws_s3_bucket.nonooutput_us_east_1.id
  policy   = format(local.bucket_policy, aws_s3_bucket.nonooutput_us_east_1.arn)
}