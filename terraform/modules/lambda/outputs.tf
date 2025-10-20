output "beta_function_name" {
  description = "Name of the beta Lambda function"
  value       = aws_lambda_function.beta.function_name
}

output "beta_function_arn" {
  description = "ARN of the beta Lambda function"
  value       = aws_lambda_function.beta.arn
}

output "beta_function_url" {
  description = "Function URL of the beta Lambda"
  value       = aws_lambda_function_url.beta.function_url
}

output "prod_function_name" {
  description = "Name of the prod Lambda function"
  value       = aws_lambda_function.prod.function_name
}

output "prod_function_arn" {
  description = "ARN of the prod Lambda function"
  value       = aws_lambda_function.prod.arn
}

output "prod_function_url" {
  description = "Function URL of the prod Lambda"
  value       = aws_lambda_function_url.prod.function_url
}