resource "aws_cloudfront_distribution" "nono_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"
  http_version        = "http2"

  origin {
    domain_name = "nonooutput.s3.ap-northeast-2.amazonaws.com"
    origin_id   = "nonooutput-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.nono_oai.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = "nonooutput-ca-central-1.s3.ca-central-1.amazonaws.com"
    origin_id   = "nonooutput-ca-central-1-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.nono_oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "nonooutput-origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_cloudfront_origin_access_identity" "nono_oai" {
  comment = "OAI for nonooutput S3 bucket"
}

# S3 버킷 정책 업데이트 (nonooutput 버킷)
resource "aws_s3_bucket_policy" "nonooutput_policy" {
  bucket = "nonooutput"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAI"
        Effect    = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.nono_oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::nonooutput/*"
      }
    ]
  })
}

# S3 버킷 정책 업데이트 (nonooutput-ca-central-1 버킷)
resource "aws_s3_bucket_policy" "nonooutput_ca_central_1_policy" {
  bucket = "nonooutput-ca-central-1"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAI"
        Effect    = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.nono_oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::nonooutput-ca-central-1/*"
      }
    ]
  })
}
