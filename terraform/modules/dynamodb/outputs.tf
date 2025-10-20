output "beta_table_name" {
  description = "Name of the beta DynamoDB table"
  value       = aws_dynamodb_table.beta_results.name
}

output "beta_table_arn" {
  description = "ARN of the beta DynamoDB table"
  value       = aws_dynamodb_table.beta_results.arn
}

output "prod_table_name" {
  description = "Name of the prod DynamoDB table"
  value       = aws_dynamodb_table.prod_results.name
}

output "prod_table_arn" {
  description = "ARN of the prod DynamoDB table"
  value       = aws_dynamodb_table.prod_results.arn
}