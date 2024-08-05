resource "aws_cloudfront_distribution" "nono_distribution" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2"
  price_class     = "PriceClass_All"
  depends_on = [
    aws_lambda_function.create_mediaconvert_job,
    aws_s3_bucket.nonooutput,
    aws_s3_bucket.americanono2
  ]

  origin {
    domain_name = "nonooutput.s3.ap-northeast-2.amazonaws.com"
    origin_id   = "nonooutput-origin"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.nono_oai.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = "americanono2.s3.us-east-1.amazonaws.com"
    origin_id   = "americanono2-origin"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.nono_oai.cloudfront_access_identity_path
    }
  }

  origin_group {
    origin_id = "nono-origin-group"
    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }
    member {
      origin_id = "nonooutput-origin"
    }
    member {
      origin_id = "americanono2-origin"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "nono-origin-group"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
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
  comment = "OAI for nonooutput and americanono2 buckets"
}