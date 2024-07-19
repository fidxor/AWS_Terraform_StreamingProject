provider "aws" {
  region = "ap-northeast-2"  # 또는 사용하려는 리전
}

resource "aws_lambda_function" "create_mediaconvert_job" {
  filename      = "lambda_function.zip"  # Lambda 함수 코드를 포함한 ZIP 파일
  function_name = "create_mediaconvert_job"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300  # 5분
  memory_size   = 128
  architectures = ["x86_64"]

  environment {
    variables = {
      Application        = "VOD-HLS"
      DEFAULT_VIDEO_NAME = "default.mp4"
      DestinationBucket  = "nonooutput"
      MediaConvertRole   = "arn:aws:iam::975049989858:role/role_mediaconvert"
    }
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source {
    content  = file("lambda_function.py")
    filename = "lambda_function.py"
  }
  source {
    content  = file("job.json")
    filename = "job.json"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_mediaconvert_role"

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy" "lambda_mediaconvert" {
  name = "lambda_mediaconvert_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mediaconvert:*",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::975049989858:role/role_mediaconvert"
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_mediaconvert_job.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::nonoinput"
  source_account = "975049989858"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "nonoinput"

  lambda_function {
    lambda_function_arn = aws_lambda_function.create_mediaconvert_job.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "vod/"
  }
}
