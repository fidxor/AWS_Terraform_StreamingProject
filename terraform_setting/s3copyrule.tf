resource "aws_s3_bucket_versioning" "nonooutput" {
  bucket = aws_s3_bucket.nonooutput.id
  versioning_configuration {
    status = "Enabled"
  }
}


locals {
  replication_rules = [
    {
      id     = "nonooutput-to-ap-northeast-2"
      destination_bucket = aws_s3_bucket.nonooutput_ap_northeast_2.arn
    },
    {
      id     = "nonooutput-to-ca-central-1"
      destination_bucket = aws_s3_bucket.nonooutput_ca_central_1.arn
    },
    {
      id     = "nonooutput-to-us-east-1"
      destination_bucket = aws_s3_bucket.nonooutput_us_east_1.arn
    }
  ]
}

resource "aws_iam_role" "replication" {
  name = "s3-bucket-replication-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "replication" {
  name = "s3-bucket-replication-policy-${random_string.suffix.result}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.nonooutput.arn,
          aws_s3_bucket.nonooutput_ap_northeast_2.arn,
          aws_s3_bucket.nonooutput_ca_central_1.arn,
          aws_s3_bucket.nonooutput_us_east_1.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.nonooutput.arn}/*",
          "${aws_s3_bucket.nonooutput_ap_northeast_2.arn}/*",
          "${aws_s3_bucket.nonooutput_ca_central_1.arn}/*",
          "${aws_s3_bucket.nonooutput_us_east_1.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.nonooutput_ap_northeast_2.arn}/*",
          "${aws_s3_bucket.nonooutput_ca_central_1.arn}/*",
          "${aws_s3_bucket.nonooutput_us_east_1.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  policy_arn = aws_iam_policy.replication.arn
  role       = aws_iam_role.replication.name
}

#신규 추가
resource "time_sleep" "wait_for_versioning" {
  depends_on = [
    aws_s3_bucket_versioning.nonooutput,
    aws_s3_bucket_versioning.nonooutput_ap_northeast_2,
    aws_s3_bucket_versioning.nonooutput_us_east_1,
    aws_s3_bucket_versioning.nonooutput_ca_central_1
  ]

  create_duration = "30s"
}
#여기까지

resource "aws_s3_bucket_replication_configuration" "nonooutput_replication" {
  depends_on = [
    aws_s3_bucket_versioning.nonooutput,
    aws_s3_bucket_versioning.nonooutput_ap_northeast_2,
    aws_s3_bucket_versioning.nonooutput_us_east_1,
    aws_s3_bucket_versioning.nonooutput_ca_central_1,
    aws_iam_role_policy_attachment.replication,
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.nonooutput.id

  dynamic "rule" {
    for_each = local.replication_rules
    content {
      id       = rule.value.id
      status   = "Enabled"
      priority = index(local.replication_rules, rule.value) + 1

      # 빈 filter 블록을 사용하여 모든 객체에 적용
      filter {}

      delete_marker_replication {
        status = "Enabled"
      }

      destination {
        bucket        = rule.value.destination_bucket
        storage_class = "STANDARD"
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}