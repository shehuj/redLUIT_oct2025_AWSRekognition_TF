#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_ORG=""
GITHUB_REPO=""
AWS_REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="GitHubActionsRole"
POLICY_NAME="GitHubActionsPolicy"

print_header() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Get GitHub repository information
get_github_info() {
    print_header "Getting GitHub Repository Information"
    
    # Try to get from git remote
    if git remote get-url origin &> /dev/null; then
        REMOTE_URL=$(git remote get-url origin)
        
        # Parse GitHub org and repo from URL
        if [[ $REMOTE_URL =~ github.com[:/]([^/]+)/([^/.]+) ]]; then
            GITHUB_ORG="${BASH_REMATCH[1]}"
            GITHUB_REPO="${BASH_REMATCH[2]}"
            print_success "Detected from git remote:"
            echo "   Organization: $GITHUB_ORG"
            echo "   Repository: $GITHUB_REPO"
        fi
    fi
    
    # Prompt for confirmation or input
    echo ""
    read -p "GitHub Organization/Username [$GITHUB_ORG]: " INPUT_ORG
    GITHUB_ORG="${INPUT_ORG:-$GITHUB_ORG}"
    
    read -p "GitHub Repository Name [$GITHUB_REPO]: " INPUT_REPO
    GITHUB_REPO="${INPUT_REPO:-$GITHUB_REPO}"
    
    if [ -z "$GITHUB_ORG" ] || [ -z "$GITHUB_REPO" ]; then
        print_error "GitHub organization and repository are required"
        exit 1
    fi
    
    echo ""
    read -p "AWS Region [$AWS_REGION]: " INPUT_REGION
    AWS_REGION="${INPUT_REGION:-$AWS_REGION}"
    
    echo ""
    read -p "IAM Role Name [$ROLE_NAME]: " INPUT_ROLE
    ROLE_NAME="${INPUT_ROLE:-$ROLE_NAME}"
    
    print_info "Configuration:"
    echo "   GitHub: $GITHUB_ORG/$GITHUB_REPO"
    echo "   AWS Region: $AWS_REGION"
    echo "   Role Name: $ROLE_NAME"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check AWS CLI
    if command -v aws &> /dev/null; then
        print_success "AWS CLI installed"
        AWS_VERSION=$(aws --version | cut -d' ' -f1)
        echo "   Version: $AWS_VERSION"
    else
        print_error "AWS CLI not found"
        echo "   Install: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        print_success "AWS credentials configured"
        echo "   Account ID: $ACCOUNT_ID"
    else
        print_error "AWS credentials not configured"
        echo "   Run: aws configure"
        exit 1
    fi
    
    # Check jq
    if command -v jq &> /dev/null; then
        print_success "jq installed"
    else
        print_warning "jq not found (optional, but recommended)"
        echo "   Install: apt-get install jq (Ubuntu) or brew install jq (macOS)"
    fi
    
    echo ""
}

# Create OIDC Identity Provider
create_oidc_provider() {
    print_header "Creating OIDC Identity Provider"
    
    OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
    THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
    
    # Check if provider already exists
    PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
    
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" &> /dev/null; then
        print_warning "OIDC provider already exists"
        echo "   ARN: $PROVIDER_ARN"
    else
        print_info "Creating OIDC provider..."
        
        aws iam create-open-id-connect-provider \
            --url "https://${OIDC_PROVIDER_URL}" \
            --client-id-list "sts.amazonaws.com" \
            --thumbprint-list "$THUMBPRINT" \
            --tags Key=Name,Value=GitHubActionsOIDC Key=ManagedBy,Value=Script
        
        print_success "OIDC provider created"
        echo "   ARN: $PROVIDER_ARN"
    fi
    
    echo ""
}

# Create IAM policy
create_iam_policy() {
    print_header "Creating IAM Policy"
    
    # Get Terraform state bucket and DynamoDB table if they exist
    TERRAFORM_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'terraform-state')].Name | [0]" --output text 2>/dev/null || echo "*")
    TERRAFORM_TABLE=$(aws dynamodb list-tables --query "TableNames[?contains(@, 'terraform-lock') || contains(@, 'terraform-state-lock')] | [0]" --output text 2>/dev/null || echo "*")
    
    # Get Rekognition bucket if it exists
    REKOGNITION_BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'rekognition')].Name | [0]" --output text 2>/dev/null || echo "*")
    
    POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketNotification",
        "s3:GetBucketNotification",
        "s3:PutBucketEncryption",
        "s3:GetBucketEncryption",
        "s3:PutLifecycleConfiguration",
        "s3:GetLifecycleConfiguration"
      ],
      "Resource": [
        "arn:aws:s3:::*rekognition*",
        "arn:aws:s3:::*rekognition*/*",
        "arn:aws:s3:::*terraform-state*",
        "arn:aws:s3:::*terraform-state*/*"
      ]
    },
    {
      "Sid": "RekognitionAccess",
      "Effect": "Allow",
      "Action": [
        "rekognition:DetectLabels",
        "rekognition:DetectText",
        "rekognition:DetectFaces",
        "rekognition:RecognizeCelebrities"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaAccess",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:ListFunctions",
        "lambda:InvokeFunction",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:GetPolicy",
        "lambda:CreateFunctionUrlConfig",
        "lambda:DeleteFunctionUrlConfig",
        "lambda:GetFunctionUrlConfig",
        "lambda:UpdateFunctionUrlConfig",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:ListTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDBAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:UpdateTable",
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:DeleteItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:UpdateTimeToLive",
        "dynamodb:DescribeContinuousBackups",
        "dynamodb:UpdateContinuousBackups",
        "dynamodb:ListTables",
        "dynamodb:ListTagsOfResource",
        "dynamodb:TagResource",
        "dynamodb:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMAccess",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:GetUser",
        "iam:CreateAccessKey",
        "iam:DeleteAccessKey",
        "iam:PutUserPolicy",
        "iam:GetUserPolicy",
        "iam:DeleteUserPolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagUser",
        "iam:UntagUser",
        "iam:TagPolicy",
        "iam:UntagPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup",
        "logs:ListTagsLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSAccess",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${TERRAFORM_BUCKET}",
        "arn:aws:s3:::${TERRAFORM_BUCKET}/*"
      ]
    },
    {
      "Sid": "TerraformLockAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/${TERRAFORM_TABLE}"
    }
  ]
}
EOF
)
    
    # Save policy to file
    echo "$POLICY_DOCUMENT" > /tmp/github-actions-policy.json
    
    # Check if policy exists
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
        print_warning "Policy already exists: $POLICY_NAME"
        
        # Get the default version
        DEFAULT_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" --query 'Policy.DefaultVersionId' --output text)
        
        # Create new version
        print_info "Creating new policy version..."
        aws iam create-policy-version \
            --policy-arn "$POLICY_ARN" \
            --policy-document file:///tmp/github-actions-policy.json \
            --set-as-default
        
        print_success "Policy updated to new version"
    else
        print_info "Creating IAM policy..."
        
        aws iam create-policy \
            --policy-name "$POLICY_NAME" \
            --policy-document file:///tmp/github-actions-policy.json \
            --description "Policy for GitHub Actions to manage Rekognition pipeline infrastructure" \
            --tags Key=Name,Value=GitHubActionsPolicy Key=ManagedBy,Value=Script
        
        print_success "IAM policy created"
    fi
    
    echo "   Policy ARN: $POLICY_ARN"
    echo ""
    
    # Clean up temp file
    rm /tmp/github-actions-policy.json
}

# Create IAM role with trust policy
create_iam_role() {
    print_header "Creating IAM Role"
    
    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)
    
    # Save trust policy to file
    echo "$TRUST_POLICY" > /tmp/trust-policy.json
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        print_warning "Role already exists: $ROLE_NAME"
        
        # Update trust policy
        print_info "Updating trust policy..."
        aws iam update-assume-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-document file:///tmp/trust-policy.json
        
        print_success "Trust policy updated"
    else
        print_info "Creating IAM role..."
        
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file:///tmp/trust-policy.json \
            --description "Role for GitHub Actions to manage Rekognition pipeline" \
            --tags Key=Name,Value=GitHubActionsRole Key=ManagedBy,Value=Script
        
        print_success "IAM role created"
    fi
    
    echo "   Role ARN: $ROLE_ARN"
    echo ""
    
    # Clean up temp file
    rm /tmp/trust-policy.json
}

# Attach policy to role
attach_policy_to_role() {
    print_header "Attaching Policy to Role"
    
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    print_info "Attaching policy to role..."
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$POLICY_ARN"
    
    print_success "Policy attached to role"
    echo ""
}

# Generate GitHub Actions workflow snippet
generate_workflow_snippet() {
    print_header "GitHub Actions Configuration"
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    
    print_info "Add this to your GitHub Actions workflows:"
    
    cat <<EOF

${GREEN}# Add to your workflow YAML file:${NC}

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    # Required for OIDC
    permissions:
      id-token: write
      contents: read
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${ROLE_ARN}
          aws-region: ${AWS_REGION}
      
      - name: Verify AWS identity
        run: aws sts get-caller-identity

EOF

    echo ""
}

# Update existing workflows
update_workflows() {
    print_header "Updating Existing Workflows"
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    
    if [ ! -d ".github/workflows" ]; then
        print_warning "No .github/workflows directory found"
        echo "   Skipping workflow updates"
        return
    fi
    
    print_info "Found workflows:"
    ls -1 .github/workflows/*.yml 2>/dev/null | sed 's/^/   - /' || echo "   (none)"
    
    echo ""
    read -p "Update workflows to use OIDC? (y/N): " UPDATE_WORKFLOWS
    
    if [[ "$UPDATE_WORKFLOWS" =~ ^[Yy]$ ]]; then
        for workflow in .github/workflows/*.yml; do
            if [ -f "$workflow" ]; then
                WORKFLOW_NAME=$(basename "$workflow")
                print_info "Updating $WORKFLOW_NAME..."
                
                # Create backup
                cp "$workflow" "${workflow}.backup"
                
                # Update workflow (simple replacement - may need manual review)
                if grep -q "aws-actions/configure-aws-credentials" "$workflow"; then
                    # Replace the configure-aws-credentials step
                    sed -i.tmp "s|aws-access-key-id:.*|role-to-assume: ${ROLE_ARN}|g" "$workflow"
                    sed -i.tmp "s|aws-secret-access-key:.*||g" "$workflow"
                    sed -i.tmp "/\${{ secrets.AWS_SECRET_ACCESS_KEY }}/d" "$workflow"
                    
                    # Add permissions if not present
                    if ! grep -q "permissions:" "$workflow"; then
                        # This is complex - better to do manually
                        print_warning "Please manually add permissions section to $WORKFLOW_NAME"
                    fi
                    
                    rm -f "${workflow}.tmp"
                    print_success "Updated $WORKFLOW_NAME (backup saved as ${WORKFLOW_NAME}.backup)"
                else
                    print_warning "Workflow doesn't use aws-actions/configure-aws-credentials"
                    rm "${workflow}.backup"
                fi
            fi
        done
        
        print_warning "Please review and test updated workflows before committing!"
    fi
    
    echo ""
}

# Remove old secrets (optional)
remove_old_secrets() {
    print_header "Cleanup Old Secrets"
    
    print_info "With OIDC, these secrets are no longer needed:"
    echo "   - AWS_ACCESS_KEY_ID"
    echo "   - AWS_SECRET_ACCESS_KEY"
    echo ""
    
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        print_info "You can remove them with:"
        echo "   gh secret delete AWS_ACCESS_KEY_ID"
        echo "   gh secret delete AWS_SECRET_ACCESS_KEY"
        echo ""
        
        read -p "Remove AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY secrets now? (y/N): " REMOVE_SECRETS
        
        if [[ "$REMOVE_SECRETS" =~ ^[Yy]$ ]]; then
            gh secret delete AWS_ACCESS_KEY_ID 2>/dev/null && print_success "Deleted AWS_ACCESS_KEY_ID" || print_warning "AWS_ACCESS_KEY_ID not found"
            gh secret delete AWS_SECRET_ACCESS_KEY 2>/dev/null && print_success "Deleted AWS_SECRET_ACCESS_KEY" || print_warning "AWS_SECRET_ACCESS_KEY not found"
        fi
    else
        print_warning "GitHub CLI not available or not authenticated"
        echo "   Install: https://cli.github.com/"
    fi
    
    echo ""
}

# Test the setup
test_setup() {
    print_header "Testing Setup"
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    
    print_info "Testing if role can be assumed..."
    
    # This won't work locally without GitHub OIDC token, but we can verify the role exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        print_success "Role exists and is accessible"
    else
        print_error "Role not accessible"
        return 1
    fi
    
    # Verify trust policy
    TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json)
    
    if echo "$TRUST_POLICY" | grep -q "token.actions.githubusercontent.com"; then
        print_success "Trust policy configured for GitHub OIDC"
    else
        print_error "Trust policy not configured correctly"
        return 1
    fi
    
    # Verify policy attachment
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyName' --output text)
    
    if echo "$ATTACHED_POLICIES" | grep -q "$POLICY_NAME"; then
        print_success "Policy attached to role"
    else
        print_error "Policy not attached to role"
        return 1
    fi
    
    print_success "Setup appears to be configured correctly"
    print_info "Test by running a GitHub Actions workflow"
    
    echo ""
}

# Summary
print_summary() {
    print_header "Setup Complete!"
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    
    cat <<EOF
${GREEN}✓ OIDC Provider created${NC}
${GREEN}✓ IAM Policy created: ${POLICY_NAME}${NC}
${GREEN}✓ IAM Role created: ${ROLE_NAME}${NC}
${GREEN}✓ Policy attached to role${NC}

${BLUE}Role ARN:${NC} ${ROLE_ARN}
${BLUE}AWS Region:${NC} ${AWS_REGION}
${BLUE}GitHub Repo:${NC} ${GITHUB_ORG}/${GITHUB_REPO}

${YELLOW}Next Steps:${NC}
1. Update your GitHub Actions workflows to use OIDC (see example above)
2. Add this to workflow permissions:
   ${BLUE}permissions:
     id-token: write
     contents: read${NC}
3. Test by running a workflow
4. Remove old AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY secrets

${YELLOW}Documentation:${NC}
- AWS OIDC: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- Configure AWS Credentials: https://github.com/aws-actions/configure-aws-credentials

EOF
}

# Main execution
main() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   GitHub Actions OIDC Setup for AWS                      ║
║   Rekognition Pipeline Configuration                     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    get_github_info
    check_prerequisites
    
    echo ""
    read -p "Proceed with setup? (y/N): " PROCEED
    
    if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled"
        exit 0
    fi
    
    create_oidc_provider
    create_iam_policy
    create_iam_role
    attach_policy_to_role
    test_setup
    generate_workflow_snippet
    update_workflows
    remove_old_secrets
    print_summary
    
    print_success "All done! 🎉"
}

# Run main function
main "$@"