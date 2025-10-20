variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (beta or prod)"
  type        = string
}

variable "bucket_suffix" {
  description = "Random suffix for bucket uniqueness"
  type        = string
}