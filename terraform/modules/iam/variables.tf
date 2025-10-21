variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (beta or prod)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
  default = "values('s3_bucket_arn')"
  sensitive   = true
}

variable "dynamodb_table_arns" {
  description = "Map of DynamoDB table ARNs"
  type = object({
    beta = string
    prod = string
  })
}