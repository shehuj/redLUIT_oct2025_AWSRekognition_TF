variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (beta or prod)"
  type        = string
  
  validation {
    condition     = contains(["beta", "prod"], var.environment)
    error_message = "Environment must be either 'beta' or 'prod'."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions (MB)"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions (seconds)"
  type        = number
  default     = 60
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "max_rekognition_labels" {
  description = "Maximum number of labels to return from Rekognition"
  type        = number
  default     = 10
}

variable "min_confidence" {
  description = "Minimum confidence threshold for Rekognition labels"
  type        = number
  default     = 70.0
}