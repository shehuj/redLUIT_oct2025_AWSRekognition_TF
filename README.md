# redLUIT_oct2025_AWSRekognition_TF

# Amazon Rekognition CI/CD Pipeline with Terraform

Complete implementation guide for Pixel Learning Co.'s automated image classification system using Amazon Rekognition, S3, Lambda, DynamoDB, and GitHub Actions.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Step-by-Step Implementation](#step-by-step-implementation)
4. [Testing & Validation](#testing--validation)
5. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools
- AWS Account with appropriate permissions
- Terraform >= 1.0
- AWS CLI configured
- GitHub repository
- Python 3.9+

### AWS Permissions Required
- S3: CreateBucket, PutObject, GetObject
- DynamoDB: CreateTable, PutItem, GetItem
- Lambda: CreateFunction, UpdateFunctionCode
- IAM: CreateRole, AttachRolePolicy
- Rekognition: DetectLabels

## Project Structure

```
rekognition-pipeline/
├── README.md
├── terraform/
│   ├── main.tf                    # Root module configuration
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── backend.tf                 # Terraform state backend
│   ├── modules/
│   │   ├── s3/                    # S3 bucket module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── dynamodb/              # DynamoDB tables module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── lambda/                # Lambda functions module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── iam/                   # IAM roles and policies module
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── environments/
│       ├── beta.tfvars
│       └── prod.tfvars
├── lambda/
│   ├── rekognition_handler.py     # Lambda function code
│   └── requirements.txt
├── scripts/
│   └── analyze_image.py           # Local analysis script (foundational)
├── .github/
│   └── workflows/
│       ├── on_pull_request.yml    # PR workflow
│       ├── on_merge.yml           # Merge workflow
│       └── deploy_infrastructure.yml  # Infrastructure deployment
├── images/                        # Sample images directory
│   └── .gitkeep
└── .gitignore
```

## Step-by-Step Implementation

### Step 1: Initialize Project Structure

```bash
# Create project directory
mkdir rekognition-pipeline
cd rekognition-pipeline

# Create directory structure
mkdir -p terraform/modules/{s3,dynamodb,lambda,iam}
mkdir -p terraform/environments
mkdir -p lambda
mkdir -p scripts
mkdir -p .github/workflows
mkdir -p images
```

### Step 2: Configure AWS Backend

Create `terraform/backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "pixel-learning-terraform-state"
    key            = "rekognition-pipeline/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Action Required**: Create the S3 bucket and DynamoDB table for state management:
```bash
aws s3 mb s3://pixel-learning-terraform-state --region us-east-1
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Step 3: Configure GitHub Secrets

In your GitHub repository, add the following secrets (Settings → Secrets and variables → Actions):

```
AWS_ACCESS_KEY_ID=<your-access-key>
AWS_SECRET_ACCESS_KEY=<your-secret-key>
AWS_REGION=us-east-1
S3_BUCKET=pixel-learning-rekognition-images
DYNAMODB_TABLE_BETA=beta_results
DYNAMODB_TABLE_PROD=prod_results
```

### Step 4: Deploy Infrastructure

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Review the plan for beta environment
terraform plan -var-file=environments/beta.tfvars

# Apply beta infrastructure
terraform apply -var-file=environments/beta.tfvars

# Apply prod infrastructure
terraform apply -var-file=environments/prod.tfvars
```

### Step 5: Test the Pipeline

#### Foundational Testing (Direct GitHub Actions)

```bash
# Add a test image
cp /path/to/your/image.jpg images/test_balloon.jpg

# Create a new branch
git checkout -b test-rekognition
git add images/test_balloon.jpg
git commit -m "Add test image"
git push origin test-rekognition

# Create a Pull Request
# This triggers on_pull_request.yml → writes to beta_results
```

#### Advanced Testing (Lambda Event-Driven)

```bash
# The workflow will upload to S3, triggering Lambda automatically
# Check DynamoDB for results:
aws dynamodb scan --table-name beta_results --region us-east-1
```

### Step 6: Verify Results

#### Check DynamoDB Tables

```bash
# Beta results
aws dynamodb scan \
  --table-name beta_results \
  --region us-east-1 \
  --output table

# Production results (after merge)
aws dynamodb scan \
  --table-name prod_results \
  --region us-east-1 \
  --output table
```

#### Check S3 Uploads

```bash
aws s3 ls s3://pixel-learning-rekognition-images/rekognition-input/beta/
aws s3 ls s3://pixel-learning-rekognition-images/rekognition-input/prod/
```

#### Check Lambda Logs

```bash
# Beta Lambda logs
aws logs tail /aws/lambda/rekognition-beta-handler --follow

# Prod Lambda logs
aws logs tail /aws/lambda/rekognition-prod-handler --follow
```

## Testing & Validation

### Local Testing (Foundational)

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
export AWS_REGION=us-east-1
export S3_BUCKET=pixel-learning-rekognition-images
export DYNAMODB_TABLE=beta_results

# Run the analysis script
python scripts/analyze_image.py images/test_balloon.jpg beta
```

### CI/CD Testing

1. **Pull Request Flow**:
   - Create branch → Add image → Push → Open PR
   - GitHub Actions runs `on_pull_request.yml`
   - Uploads to `rekognition-input/beta/`
   - Lambda processes and writes to `beta_results`

2. **Merge Flow**:
   - Merge PR to main
   - GitHub Actions runs `on_merge.yml`
   - Uploads to `rekognition-input/prod/`
   - Lambda processes and writes to `prod_results`

### Validation Checklist

- [ ] S3 bucket created with event notifications
- [ ] DynamoDB tables (beta_results, prod_results) exist
- [ ] Lambda functions deployed and executable
- [ ] IAM roles have correct permissions
- [ ] GitHub Actions workflows trigger correctly
- [ ] Images upload to correct S3 prefixes
- [ ] Lambda functions process images successfully
- [ ] Results appear in correct DynamoDB tables
- [ ] Labels include confidence scores and timestamps

## Troubleshooting

### Common Issues

#### 1. Lambda Function Not Triggered
```bash
# Check S3 event notification configuration
aws s3api get-bucket-notification-configuration \
  --bucket pixel-learning-rekognition-images

# Verify Lambda permissions
aws lambda get-policy \
  --function-name rekognition-beta-handler
```

#### 2. Permission Denied Errors
```bash
# Check IAM role attached to Lambda
aws lambda get-function-configuration \
  --function-name rekognition-beta-handler \
  --query 'Role'

# Review IAM policy
aws iam get-role-policy \
  --role-name rekognition-lambda-role \
  --policy-name rekognition-lambda-policy
```

#### 3. DynamoDB Write Failures
```bash
# Check CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/rekognition-beta-handler \
  --filter-pattern "ERROR"
```

#### 4. GitHub Actions Failures
- Verify all secrets are configured
- Check workflow syntax in YAML files
- Review Actions logs in GitHub UI
- Ensure AWS credentials have necessary permissions

### Debug Commands

```bash
# Test Lambda function manually
aws lambda invoke \
  --function-name rekognition-beta-handler \
  --payload '{"Records":[{"s3":{"bucket":{"name":"pixel-learning-rekognition-images"},"object":{"key":"rekognition-input/beta/test.jpg"}}}]}' \
  response.json

# Check Rekognition service availability
aws rekognition detect-labels \
  --image '{"S3Object":{"Bucket":"pixel-learning-rekognition-images","Name":"rekognition-input/beta/test.jpg"}}' \
  --max-labels 10
```

## Cost Estimates

- **S3**: ~$0.023/GB/month
- **DynamoDB**: Free tier covers 25GB, then $0.25/GB/month
- **Lambda**: Free tier covers 1M requests/month
- **Rekognition**: $1.00 per 1,000 images analyzed

Expected monthly cost for moderate use: **$5-20**

## Security Best Practices

1. **Least Privilege**: IAM roles have minimum required permissions
2. **Encryption**: S3 bucket encryption enabled
3. **Secret Management**: No hardcoded credentials
4. **Network Security**: Lambda functions in VPC (optional, for advanced security)
5. **Logging**: CloudWatch logs enabled for audit trail

## Next Steps

1. **Monitoring**: Set up CloudWatch alarms for Lambda errors
2. **Optimization**: Adjust Lambda memory/timeout based on usage
3. **Scaling**: Consider batch processing for large image volumes
4. **Enhancement**: Add custom labels or text detection features
5. **CI/CD**: Automate infrastructure updates through GitHub Actions

## Resources

- [AWS Rekognition Documentation](https://docs.aws.amazon.com/rekognition/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## Support

For issues or questions:
1. Check CloudWatch Logs
2. Review Terraform plan output
3. Validate AWS permissions
4. Contact DevOps team
