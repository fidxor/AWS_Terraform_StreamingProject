provider "aws" {
  region = "ap-northeast-2"
}

# IAM 역할 생성
resource "aws_iam_role" "lambda_vod_execution" {
  name = "lambda_vod_execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# AWSLambdaBasicExecutionRole 정책 연결
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_vod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda 함수 호출 정책
resource "aws_iam_role_policy" "lambda_invoke_policy" {
  name = "lambda_invoke_policy"
  role = aws_iam_role.lambda_vod_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:ap-northeast-2:975049989858:function:create_mediaconvert_job*"
      }
    ]
  })
}

# 추가 권한 정책
resource "aws_iam_role_policy" "additional_permissions" {
  name = "additional_permissions"
  role = aws_iam_role.lambda_vod_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = ["arn:aws:iam::975049989858:role/role_mediaconvert"]
      },
      {
        Sid    = "MediaConvertService"
        Effect = "Allow"
        Action = ["mediaconvert:*"]
        Resource = ["*"]
      },
      {
        Sid    = "S3FullAccess"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = ["*"]
      },
      {
        Sid    = "S3GetObject"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "arn:aws:s3:::nonooutput/*",
          "arn:aws:s3:::nonooutput-us-east-1/*",
          "arn:aws:s3:::nonooutput-ca-central-1/*"
        ]
      }
    ]
  })
}
