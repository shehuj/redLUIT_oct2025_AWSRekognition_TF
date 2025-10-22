terraform {
  backend "s3" {
    # Backend configuration should be provided via backend config file or CLI
    # Example: terraform init -backend-config=backend-config.hcl
    # To avoid hardcoding sensitive info in this file.    
    # Uncomment and modify these values or use a backend config file:
    bucket         = "ec2-shutdown-lambda-bucket"
    key            = "rekognition-pipeline/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = false
    dynamodb_table = "terraform-state-lock"

  }
}

# Create a backend-config.hcl file with:
# bucket         = "your-terraform-state-bucket"
# key            = "rekognition-pipeline/terraform.tfstate"
# region         = "us-east-1"
# encrypt        = true
# dynamodb_table = "terraform-state-lock"
#
# Then initialize with:
# terraform init -backend-config=backend-config.hcl