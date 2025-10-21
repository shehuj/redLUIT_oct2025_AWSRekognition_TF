# Event-Driven Image Classification Pipeline

A serverless, event-driven architecture for automated image classification using AWS Lambda, S3, Rekognition, and DynamoDB.

## Overview

This project implements an automated image classification pipeline that processes images uploaded to S3, analyzes them using Amazon Rekognition, and stores results in DynamoDB. The architecture is fully event-driven with separate beta and production environments.

## Architecture

### Event Flow

1. **GitHub Actions** uploads images to S3 based on branch:
   - Pull requests → `rekognition-input/beta/`
   - Merges to main → `rekognition-input/prod/`

2. **S3 Event Notification** automatically triggers the appropriate Lambda function

3. **Lambda Function** processes the image:
   - Calls Amazon Rekognition to detect labels
   - Stores results in environment-specific DynamoDB table

4. **GitHub Actions** validates processing by querying DynamoDB

### Key Benefits

- ✅ **Fully Decoupled**: GitHub Actions only handles uploads, Lambda handles processing
- ✅ **Event-Driven**: Automatic processing via S3 triggers
- ✅ **Scalable**: Lambda auto-scales based on upload volume
- ✅ **Environment Separation**: Isolated beta and prod environments
- ✅ **Validation**: Automated checks ensure successful processing

## Components

### Lambda Functions

| Function | Trigger | DynamoDB Table |
|----------|---------|----------------|
| `rekognition-beta-handler` | `rekognition-input/beta/*` | `beta_results` |
| `rekognition-prod-handler` | `rekognition-input/prod/*` | `prod_results` |

### GitHub Actions Workflows

| Workflow | Trigger | S3 Prefix |
|----------|---------|-----------|
| `on_pull_request.yml` | Pull Request | `rekognition-input/beta/` |
| `on_merge.yml` | Push to main | `rekognition-input/prod/` |

### Infrastructure

- **S3 Bucket**: Image storage with event notifications
- **DynamoDB Tables**: Results storage (beta and prod)
- **IAM Roles**: Lambda execution and GitHub Actions permissions
- **CloudWatch**: Logging and monitoring

## Quick Start

### 1. Deploy Infrastructure

```bash
terraform init
terraform apply -var="s3_bucket_name=your-bucket-name"
```

### 2. Configure GitHub Secrets

Add to your repository secrets:
- `AWS_ROLE_ARN`: IAM role for GitHub Actions
- `S3_BUCKET`: S3 bucket name

### 3. Add Workflows

```bash
cp on_pull_request.yml .github/workflows/
cp on_merge.yml .github/workflows/
git add .github/workflows/
git commit -m "Add image processing workflows"
git push
```

### 4. Test the Pipeline

```bash
# Create test branch
git checkout -b test-pipeline

# Add test image
cp test-image.jpg images/
git add images/test-image.jpg
git commit -m "Test image processing"
git push origin test-pipeline

# Create pull request (triggers beta processing)
# Merge to main (triggers prod processing)
```

## File Structure

```
.
├── lambda_beta_handler.py          # Beta Lambda function
├── lambda_prod_handler.py          # Prod Lambda function
├── terraform_infrastructure.tf     # Infrastructure as Code
├── on_pull_request.yml            # Beta workflow
├── on_merge.yml                   # Prod workflow
├── DEPLOYMENT_GUIDE.md            # Detailed deployment instructions
└── README.md                      # This file
```

## How It Works

### Beta Environment (Pull Requests)

1. Developer creates PR with new/modified images
2. Workflow uploads images to `rekognition-input/beta/`
3. S3 event triggers `rekognition-beta-handler` Lambda
4. Lambda analyzes image with Rekognition
5. Results stored in `beta_results` DynamoDB table
6. Workflow validates processing and comments on PR

### Production Environment (Merges)

1. PR merged to main branch
2. Workflow uploads images to `rekognition-input/prod/`
3. S3 event triggers `rekognition-prod-handler` Lambda
4. Lambda analyzes image with Rekognition
5. Results stored in `prod_results` DynamoDB table
6. Workflow validates processing and creates summary

## Data Schema

### DynamoDB Item Structure

```json
{
  "filename": "rekognition-input/beta/image.jpg",
  "labels": [
    {
      "Name": "Dog",
      "Confidence": 98.5
    },
    {
      "Name": "Pet",
      "Confidence": 95.2
    }
  ],
  "timestamp": "2025-10-21T10:30:45Z",
  "branch": "beta",
  "environment": "beta",
  "label_count": 2,
  "analysis_method": "lambda_s3_trigger",
  "s3_bucket": "your-bucket-name"
}
```

## Monitoring

### View Lambda Logs

```bash
# Beta environment
aws logs tail /aws/lambda/rekognition-beta-handler --follow

# Production environment
aws logs tail /aws/lambda/rekognition-prod-handler --follow
```

### Query Results

```bash
# List all beta results
aws dynamodb scan --table-name beta_results

# Get specific result
aws dynamodb get-item \
  --table-name beta_results \
  --key '{"filename": {"S": "rekognition-input/beta/image.jpg"}}'
```

### CloudWatch Metrics

Monitor in AWS Console:
- Lambda invocations
- Lambda errors
- Lambda duration
- DynamoDB read/write capacity

## Cost Optimization

| Service | Optimization |
|---------|-------------|
| Lambda | 256MB memory, 60s timeout |
| DynamoDB | On-demand billing mode |
| S3 | Lifecycle policies for old images |
| CloudWatch | 7-day retention for beta, 14-day for prod |

## Comparison: Original vs Refactored

| Aspect | Original Script | Event-Driven Architecture |
|--------|----------------|---------------------------|
| **Execution** | Manual CLI or GitHub Action | Automatic via S3 events |
| **Coupling** | Tight (workflow does everything) | Loose (separation of concerns) |
| **Scalability** | Limited to workflow capacity | Auto-scales with Lambda |
| **Maintenance** | Update workflows for changes | Update Lambda functions independently |
| **Monitoring** | GitHub Actions logs only | CloudWatch + workflow logs |
| **Retry Logic** | Manual or workflow-based | Automatic Lambda retries |

## Advanced Features

### Add Error Notifications

```python
# In Lambda function
import boto3
sns = boto3.client('sns')

# On error
sns.publish(
    TopicArn='arn:aws:sns:region:account:topic',
    Subject='Image Processing Failed',
    Message=f'Failed to process {filename}'
)
```

### Implement Batch Processing

Configure S3 to batch multiple events before triggering Lambda.

### Add Custom Metadata

```bash
# In GitHub Actions workflow
aws s3 cp image.jpg s3://bucket/prefix/ \
  --metadata "owner=john,project=ml-demo"
```

## Troubleshooting

### Lambda Not Triggered

- Check S3 notification configuration: `aws s3api get-bucket-notification-configuration --bucket BUCKET`
- Verify Lambda has permission to be invoked by S3
- Ensure image is uploaded to correct prefix

### Validation Fails

- Increase wait time in workflow (default: 10 seconds)
- Check Lambda CloudWatch logs for errors
- Verify DynamoDB table name in Lambda environment variables

### Permission Errors

- Review Lambda IAM role permissions
- Check GitHub Actions role has S3 upload permissions
- Verify DynamoDB table permissions

## Contributing

1. Create feature branch
2. Add tests if applicable
3. Update documentation
4. Submit pull request (will trigger beta processing!)

## License

MIT License - see LICENSE file for details

## Support

- Review [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed setup
- Check CloudWatch logs for Lambda execution details
- Review GitHub Actions workflow runs for validation issues

## Future Enhancements

- [ ] Add SNS notifications for processing failures
- [ ] Implement image deduplication
- [ ] Add support for video analysis
- [ ] Create dashboard for metrics visualization
- [ ] Implement archival of old results
- [ ] Add unit and integration tests
- [ ] Support additional Rekognition features (faces, text, etc.)