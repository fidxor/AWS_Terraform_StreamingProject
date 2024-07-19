provider "aws" {
  region = "ap-northeast-2"  # 소스 버킷의 리전
}

resource "aws_s3_bucket" "nonooutput" {
  bucket = "nonooutput"
}

resource "aws_s3_bucket_versioning" "nonooutput" {
  bucket = aws_s3_bucket.nonooutput.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "replication" {
  name = "s3-bucket-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "replication" {
  name = "s3-bucket-replication-policy"

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
          aws_s3_bucket.nonooutput.arn
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
          "${aws_s3_bucket.nonooutput.arn}/*"
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
          "arn:aws:s3:::nonooutput-ca-central-1/*",
          "arn:aws:s3:::nonooutput-us-east-1/*",
          "arn:aws:s3:::nonooutput-ap-northeast-2/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  policy_arn = aws_iam_policy.replication.arn
  role       = aws_iam_role.replication.name
}

resource "aws_s3_bucket_replication_configuration" "replication" {
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.nonooutput.id

  rule {
    id     = "copy_ca-central-1"
    status = "Enabled"
    priority = 2

    destination {
      bucket        = "arn:aws:s3:::nonooutput-ca-central-1"
      storage_class = "STANDARD"
    }
  }

  rule {
    id     = "copy_us-east-1"
    status = "Enabled"
    priority = 1

    destination {
      bucket        = "arn:aws:s3:::nonooutput-us-east-1"
      storage_class = "STANDARD"
    }
  }

  rule {
    id     = "copy_ap-northeast-2"
    status = "Enabled"
    priority = 0

    destination {
      bucket        = "arn:aws:s3:::nonooutput-ap-northeast-2"
      storage_class = "STANDARD"
    }
  }
}
