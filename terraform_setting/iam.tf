provider "aws" {
  region = "ap-northeast-2"  # 또는 사용하려는 리전
}

# IAM 역할 생성
resource "aws_iam_role" "mediaconvert_role" {
  name = "mediaconvert_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "mediaconvert.amazonaws.com"
        }
      }
    ]
  })
}

# API Gateway Invoke 정책
resource "aws_iam_role_policy" "api_gateway_invoke_policy" {
  name = "api_gateway_invoke_policy"
  role = aws_iam_role.mediaconvert_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "execute-api:Invoke",
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:*:*:*"
      }
    ]
  })
}

# S3 Full Access 정책
resource "aws_iam_role_policy" "s3_full_access_policy" {
  name = "s3_full_access_policy"
  role = aws_iam_role.mediaconvert_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",
          "s3-object-lambda:*"
        ]
        Resource = "*"
      }
    ]
  })
}
