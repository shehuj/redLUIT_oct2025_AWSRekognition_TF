terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "PixelLearning-Rekognition"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Generate unique suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  project_name = "pixel-learning"
  common_tags = {
    Project     = "PixelLearning-Rekognition"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# DynamoDB Module - Create tables first (no dependencies)
module "dynamodb" {
  source = "./modules/dynamodb"

  project_name = local.project_name
  environment  = var.environment
}

# S3 Module - Create bucket (without event notifications yet)
module "s3" {
  source = "./modules/s3"
  #  lambda_function_arns = ""
  project_name  = local.project_name
  environment   = var.environment
  bucket_suffix = random_string.suffix.result
}

# IAM Module - Create roles and policies
module "iam" {
  source = "./modules/iam"

  project_name = local.project_name
  environment  = var.environment

  s3_bucket_arn = module.s3.bucket_arn
  dynamodb_table_arns = {
    beta = module.dynamodb.beta_table_arn
    prod = module.dynamodb.prod_table_arn
  }

  depends_on = [module.s3, module.dynamodb]
}

# Lambda Module - Create Lambda functions
module "lambda" {
  source = "./modules/lambda"

  project_name = local.project_name
  environment  = var.environment

  s3_bucket_name = module.s3.bucket_name
  s3_bucket_arn  = module.s3.bucket_arn

  dynamodb_tables = {
    beta = module.dynamodb.beta_table_name
    prod = module.dynamodb.prod_table_name
  }

  lambda_role_arn = module.iam.lambda_role_arn

  depends_on = [module.iam, module.s3, module.dynamodb]
}

# S3 Event Notifications - Add after Lambda functions exist
resource "aws_lambda_permission" "allow_s3_beta" {
  statement_id  = "AllowS3InvokeBeta"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.beta_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3.bucket_arn
}

resource "aws_lambda_permission" "allow_s3_prod" {
  statement_id  = "AllowS3InvokeProd"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.prod_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3.bucket_arn
}

resource "aws_s3_bucket_notification" "bucket_notifications" {
  bucket = module.s3.bucket_name

  lambda_function {
    id                  = "beta-trigger"
    lambda_function_arn = module.lambda.beta_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "rekognition-input/beta/"
  }

  lambda_function {
    id                  = "prod-trigger"
    lambda_function_arn = module.lambda.prod_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "rekognition-input/prod/"
  }

  depends_on = [
    aws_lambda_permission.allow_s3_beta,
    aws_lambda_permission.allow_s3_prod
  ]
}