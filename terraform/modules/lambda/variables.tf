variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (beta or prod)"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
}

variable "dynamodb_tables" {
  description = "Map of DynamoDB table names"
  type = object({
    beta = string
    prod = string
  })
}

variable "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  type        = string
}