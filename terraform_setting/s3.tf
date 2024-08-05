# Provider 설정
provider "aws" {
  region = "ap-northeast-2"  # 기본 리전 (서울)
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"  # 미국 동부 (버지니아 북부)
}

# 기존 S3 버킷 확인
data "aws_s3_bucket" "existing_nonoinput" {
  bucket = "nonoinput"
  count  = 1
}

data "aws_s3_bucket" "existing_nonooutput" {
  bucket = "nonooutput"
  count  = 1
}

data "aws_s3_bucket" "existing_americanono2" {
  provider = aws.us_east_1
  bucket   = "americanono2"
  count    = 1
}

# S3 버킷 생성 (존재하지 않는 경우에만)
resource "aws_s3_bucket" "nonoinput" {
  count  = length(data.aws_s3_bucket.existing_nonoinput) == 0 ? 1 : 0
  bucket = "nonoinput"
}

resource "aws_s3_bucket" "nonooutput" {
  count  = length(data.aws_s3_bucket.existing_nonooutput) == 0 ? 1 : 0
  bucket = "nonooutput"
}

resource "aws_s3_bucket" "americanono2" {
  provider = aws.us_east_1
  count    = length(data.aws_s3_bucket.existing_americanono2) == 0 ? 1 : 0
  bucket   = "americanono2"
}

# 공통 버킷 설정
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
  
  # 기존 버킷과 새로 생성된 버킷을 모두 포함
  all_buckets = {
    nonoinput    = length(data.aws_s3_bucket.existing_nonoinput) > 0 ? data.aws_s3_bucket.existing_nonoinput[0].id : (length(aws_s3_bucket.nonoinput) > 0 ? aws_s3_bucket.nonoinput[0].id : null)
    nonooutput   = length(data.aws_s3_bucket.existing_nonooutput) > 0 ? data.aws_s3_bucket.existing_nonooutput[0].id : (length(aws_s3_bucket.nonooutput) > 0 ? aws_s3_bucket.nonooutput[0].id : null)
    americanono2 = length(data.aws_s3_bucket.existing_americanono2) > 0 ? data.aws_s3_bucket.existing_americanono2[0].id : (length(aws_s3_bucket.americanono2) > 0 ? aws_s3_bucket.americanono2[0].id : null)
  }
}

# 버킷 소유권 제어
resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  for_each = local.all_buckets
  bucket = each.value
  rule {
    object_ownership = local.common_bucket_config.object_ownership
  }
}

# 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "bucket_public_access" {
  for_each = local.all_buckets
  bucket = each.value
  block_public_acls       = local.common_bucket_config.block_public_acls
  block_public_policy     = local.common_bucket_config.block_public_policy
  ignore_public_acls      = local.common_bucket_config.ignore_public_acls
  restrict_public_buckets = local.common_bucket_config.restrict_public_buckets
}

# 버전 관리 활성화
resource "aws_s3_bucket_versioning" "bucket_versioning" {
  for_each = local.all_buckets
  bucket = each.value
  versioning_configuration {
    status = "Enabled"
  }
}

# 서버 측 암호화 설정
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  for_each = local.all_buckets
  bucket = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = local.common_bucket_config.sse_algorithm
    }
    bucket_key_enabled = local.common_bucket_config.bucket_key_enabled
  }
}

# CORS 구성
resource "aws_s3_bucket_cors_configuration" "bucket_cors" {
  for_each = local.all_buckets
  bucket = each.value
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

# IAM 역할 생성 (S3 복제용)
resource "aws_iam_role" "replication_role" {
  name = "s3-bucket-replication-role"

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

# IAM 정책 생성 및 연결 (S3 복제용)
resource "aws_iam_role_policy" "replication_policy" {
  name = "s3-bucket-replication-policy"
  role = aws_iam_role.replication_role.id

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
          "arn:aws:s3:::${local.all_buckets["nonooutput"]}",
          "arn:aws:s3:::${local.all_buckets["americanono2"]}"
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionForReplication"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${local.all_buckets["nonooutput"]}/*",
          "arn:aws:s3:::${local.all_buckets["americanono2"]}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${local.all_buckets["nonooutput"]}/*",
          "arn:aws:s3:::${local.all_buckets["americanono2"]}/*"
        ]
      }
    ]
  })
}

# S3 버킷 복제 규칙 설정 (nonooutput에서 americanono2로)
resource "aws_s3_bucket_replication_configuration" "main_to_sub" {
  role   = aws_iam_role.replication_role.arn
  bucket = local.all_buckets["nonooutput"]

  rule {
    id     = "main-to-sub-replication"
    status = "Enabled"

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = "arn:aws:s3:::${local.all_buckets["americanono2"]}"
      storage_class = "STANDARD"
    }
  }
}

# S3 버킷 복제 규칙 설정 (americanono2에서 nonooutput으로)
resource "aws_s3_bucket_replication_configuration" "sub_to_main" {
  provider = aws.us_east_1
  role   = aws_iam_role.replication_role.arn
  bucket = local.all_buckets["americanono2"]

  rule {
    id     = "sub-to-main-replication"
    status = "Enabled"

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = "arn:aws:s3:::${local.all_buckets["nonooutput"]}"
      storage_class = "STANDARD"
    }
  }
}

# AWS Backup 볼트 생성
resource "aws_backup_vault" "main_backup_vault" {
  name = "main_backup_vault"
}

# AWS Backup 계획 생성
resource "aws_backup_plan" "main_backup_plan" {
  name = "main_backup_plan"

  rule {
    rule_name         = "daily_backups"
    target_vault_name = aws_backup_vault.main_backup_vault.name
    schedule          = "cron(0 1 * * ? *)"  # 매일 오전 1시 (UTC)

    lifecycle {
      delete_after = 30  # 30일 후 삭제
    }
  }
}

# AWS Backup 선택 생성 (nonooutput 버킷만 백업)
resource "aws_backup_selection" "main_backup_selection" {
  iam_role_arn = aws_iam_role.backup_role.arn
  name         = "main_backup_selection"
  plan_id      = aws_backup_plan.main_backup_plan.id

  resources = [
    "arn:aws:s3:::${local.all_buckets["nonooutput"]}"
  ]
}

# AWS Backup용 IAM 역할 생성
resource "aws_iam_role" "backup_role" {
  name = "main_backup_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
}

# AWS Backup용 IAM 정책 연결
resource "aws_iam_role_policy_attachment" "backup_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup_role.name
}