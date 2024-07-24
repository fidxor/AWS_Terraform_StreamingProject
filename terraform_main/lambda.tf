terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }

  source {
    content  = file("${path.module}/job.json")
    filename = "job.json"
  }
}

resource "aws_lambda_function" "create_mediaconvert_job" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "create_mediaconvert_job"
  role             = aws_iam_role.lambda_vod_execution.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      Application        = "VOD-HLS"
      DEFAULT_VIDEO_NAME = "default.mp4"
      DestinationBucket  = "nonooutput"
      MediaConvertRole   = aws_iam_role.mediaconvert_role.arn
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.create_mediaconvert_job.arn
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.nonoinput.arn
  source_account = "975049989858"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.nonoinput.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.create_mediaconvert_job.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "vod/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}