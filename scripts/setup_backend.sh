#!/bin/bash
# Script to set up Terraform backend resources

set -e

# Configuration
BACKEND_BUCKET="${1:-pixel-learning-terraform-state}"
BACKEND_TABLE="${2:-terraform-state-lock}"
AWS_REGION="${3:-us-east-1}"

echo "=================================================="
echo "Terraform Backend Setup"
echo "=================================================="
echo "Bucket: $BACKEND_BUCKET"
echo "Table:  $BACKEND_TABLE"
echo "Region: $AWS_REGION"
echo "=================================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Check if bucket exists
if aws s3 ls "s3://$BACKEND_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating S3 bucket: $BACKEND_BUCKET"
    aws s3 mb "s3://$BACKEND_BUCKET" --region "$AWS_REGION"
    
    # Enable versioning
    echo "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BACKEND_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    echo "Enabling encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BACKEND_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Block public access
    echo "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$BACKEND_BUCKET" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    echo "S3 bucket created and configured"
else
    echo "S3 bucket already exists"
fi

# Check if DynamoDB table exists
if ! aws dynamodb describe-table --table-name "$BACKEND_TABLE" --region "$AWS_REGION" &> /dev/null; then
    echo "Creating DynamoDB table: $BACKEND_TABLE"
    aws dynamodb create-table \
        --table-name "$BACKEND_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION"
    
    echo "Waiting for table to be created..."
    aws dynamodb wait table-exists \
        --table-name "$BACKEND_TABLE" \
        --region "$AWS_REGION"
    
    echo "DynamoDB table created"
else
    echo "DynamoDB table already exists"
fi

# Create backend config file
BACKEND_CONFIG_FILE="terraform/backend-config.hcl"
echo "Creating backend configuration file: $BACKEND_CONFIG_FILE"

cat > "$BACKEND_CONFIG_FILE" << EOF
bucket         = "$BACKEND_BUCKET"
key            = "rekognition-pipeline/terraform.tfstate"
region         = "$AWS_REGION"
encrypt        = true
dynamodb_table = "$BACKEND_TABLE"
EOF

echo "Backend config file created"

echo ""
echo "=================================================="
echo "Setup Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. cd terraform"
echo "2. terraform init -backend-config=backend-config.hcl"
echo "3. terraform plan -var-file=environments/beta.tfvars"
echo "4. terraform apply -var-file=environments/beta.tfvars"
echo ""
echo "Note: backend-config.hcl is gitignored for security"
echo "=================================================="