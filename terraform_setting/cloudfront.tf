resource "aws_cloudfront_distribution" "nono_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = "PriceClass_All"

  depends_on = [
    aws_lambda_function.create_mediaconvert_job,
    aws_s3_bucket.nonooutput,
    aws_s3_bucket.nonooutput_ca_central_1
  ]

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

#07.24 추가 내용 [원본 도메인 서울리전, 미국리전 추가]
  origin {
    domain_name = "nonooutput-us-east-1.s3.us-east-1.amazonaws.com"
    origin_id   = "nonooutput-us-east-1-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.nono_oai.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = "nonooutput-ap-northeast-2.s3.ap-northeast-2.amazonaws.com"
    origin_id   = "nonooutput-ap-northeast-2-origin"

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

  web_acl_id = null # WAF 비활성화
}

resource "aws_cloudfront_origin_access_identity" "nono_oai" {
  comment = "OAI for nonooutput S3 bucket"
}
