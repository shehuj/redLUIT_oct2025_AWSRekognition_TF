output "s3_bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.s3.bucket_arn
}

output "dynamodb_beta_table_name" {
  description = "Name of the beta DynamoDB table"
  value       = module.dynamodb.beta_table_name
}

output "dynamodb_prod_table_name" {
  description = "Name of the prod DynamoDB table"
  value       = module.dynamodb.prod_table_name
}

output "lambda_beta_function_name" {
  description = "Name of the beta Lambda function"
  value       = module.lambda.beta_function_name
}

output "lambda_prod_function_name" {
  description = "Name of the prod Lambda function"
  value       = module.lambda.prod_function_name
}

output "lambda_beta_function_arn" {
  description = "ARN of the beta Lambda function"
  value       = module.lambda.beta_function_arn
}

output "lambda_prod_function_arn" {
  description = "ARN of the prod Lambda function"
  value       = module.lambda.prod_function_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.iam.lambda_role_arn
}

output "github_actions_setup" {
  description = "GitHub Actions secret configuration guide"
  value = {
    S3_BUCKET           = module.s3.bucket_name
    DYNAMODB_TABLE_BETA = module.dynamodb.beta_table_name
    DYNAMODB_TABLE_PROD = module.dynamodb.prod_table_name
    AWS_REGION          = var.aws_region
  }
}