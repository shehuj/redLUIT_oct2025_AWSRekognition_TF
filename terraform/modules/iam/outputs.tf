output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "github_actions_user_name" {
  description = "Name of the GitHub Actions IAM user"
  value       = aws_iam_user.github_actions.name
}

output "github_actions_access_key_id" {
  description = "Access key ID for GitHub Actions user"
  value       = aws_iam_access_key.github_actions.id
  sensitive   = true
}

output "github_actions_secret_access_key" {
  description = "Secret access key for GitHub Actions user"
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
}