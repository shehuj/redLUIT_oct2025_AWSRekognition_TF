# DynamoDB table for beta results
resource "aws_dynamodb_table" "beta_results" {
  name           = "beta_results"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "filename"
  range_key      = "timestamp"
  
  attribute {
    name = "filename"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "S"
  }
  
  attribute {
    name = "branch"
    type = "S"
  }
  
  # Global Secondary Index for querying by branch
  global_secondary_index {
    name            = "BranchIndex"
    hash_key        = "branch"
    range_key       = "timestamp"
    projection_type = "ALL"
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Enable encryption at rest
  server_side_encryption {
    enabled = false
  }
  
  # TTL for automatic cleanup (optional - 90 days)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  tags = {
    Name        = "${var.project_name}-beta-results"
    Environment = var.environment
  }
}

# DynamoDB table for prod results
resource "aws_dynamodb_table" "prod_results" {
  name           = "prod_results"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "filename"
  range_key      = "timestamp"
  
  attribute {
    name = "filename"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "S"
  }
  
  attribute {
    name = "branch"
    type = "S"
  }
  
  # Global Secondary Index for querying by branch
  global_secondary_index {
    name            = "BranchIndex"
    hash_key        = "branch"
    range_key       = "timestamp"
    projection_type = "ALL"
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Enable encryption at rest
  server_side_encryption {
    enabled = true
  }
  
  # TTL for automatic cleanup (optional - 90 days)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  tags = {
    Name        = "${var.project_name}-prod-results"
    Environment = var.environment
  }
}