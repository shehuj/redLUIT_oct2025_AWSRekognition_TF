# Package Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/lambda"
  output_path = "${path.module}/lambda_function.zip"
}

# Beta Lambda function
resource "aws_lambda_function" "beta" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "rekognition-beta-handler"
  role             = var.lambda_role_arn
  handler          = "rekognition_handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_tables.beta
      ENVIRONMENT    = "beta"
      MAX_LABELS     = "10"
      MIN_CONFIDENCE = "70.0"
    }
  }

  tags = {
    Name        = "${var.project_name}-rekognition-beta-handler"
    Environment = "beta"
  }
}

# Prod Lambda function
resource "aws_lambda_function" "prod" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "rekognition-prod-handler"
  role             = var.lambda_role_arn
  handler          = "rekognition_handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_tables.prod
      ENVIRONMENT    = "prod"
      MAX_LABELS     = "10"
      MIN_CONFIDENCE = "70.0"
    }
  }

  tags = {
    Name        = "${var.project_name}-rekognition-prod-handler"
    Environment = "prod"
  }
}

# CloudWatch Log Group for beta Lambda
resource "aws_cloudwatch_log_group" "beta" {
  name              = "/aws/lambda/rekognition-beta-handler"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-beta-logs"
    Environment = "beta"
  }
}

# CloudWatch Log Group for prod Lambda
resource "aws_cloudwatch_log_group" "prod" {
  name              = "/aws/lambda/rekognition-prod-handler"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-prod-logs"
    Environment = "prod"
  }
}

# Lambda function URL for beta (optional - for testing)
resource "aws_lambda_function_url" "beta" {
  function_name      = aws_lambda_function.beta.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    max_age       = 86400
  }
}

# Lambda function URL for prod (optional - for testing)
resource "aws_lambda_function_url" "prod" {
  function_name      = aws_lambda_function.prod.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    max_age       = 86400
  }
}