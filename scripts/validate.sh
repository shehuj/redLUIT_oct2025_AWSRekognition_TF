#!/bin/bash
# Comprehensive testing script for the Rekognition pipeline

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_header() {
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if command -v aws &> /dev/null; then
        print_success "AWS CLI installed"
    else
        print_failure "AWS CLI not found"
        exit 1
    fi
    
    if command -v terraform &> /dev/null; then
        print_success "Terraform installed"
    else
        print_failure "Terraform not found"
        exit 1
    fi
    
    if command -v python3 &> /dev/null; then
        print_success "Python 3 installed"
    else
        print_failure "Python 3 not found"
        exit 1
    fi
    
    if command -v jq &> /dev/null; then
        print_success "jq installed"
    else
        print_info "jq not found (optional, but recommended)"
    fi
}

# Check AWS credentials
check_aws_credentials() {
    print_header "Checking AWS Credentials"
    
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        print_success "AWS credentials valid (Account: $ACCOUNT_ID)"
    else
        print_failure "AWS credentials invalid or not configured"
        exit 1
    fi
}

# Check Terraform state
check_terraform() {
    print_header "Checking Terraform Infrastructure"
    
    cd "$PROJECT_ROOT/terraform" || exit 1
    
    if [ -d ".terraform" ]; then
        print_success "Terraform initialized"
    else
        print_info "Terraform not initialized. Run: terraform init -backend-config=backend-config.hcl"
    fi
    
    # Get outputs if available
    if terraform output &> /dev/null; then
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
        BETA_TABLE=$(terraform output -raw dynamodb_beta_table_name 2>/dev/null || echo "beta_results")
        PROD_TABLE=$(terraform output -raw dynamodb_prod_table_name 2>/dev/null || echo "prod_results")
        
        if [ -n "$S3_BUCKET" ]; then
            print_success "Terraform state found"
            print_info "S3 Bucket: $S3_BUCKET"
            print_info "Beta Table: $BETA_TABLE"
            print_info "Prod Table: $PROD_TABLE"
        fi
    else
        print_info "Terraform not applied yet"
    fi
    
    cd "$PROJECT_ROOT" || exit 1
}

# Check S3 bucket
check_s3() {
    print_header "Checking S3 Bucket"
    
    if [ -z "$S3_BUCKET" ]; then
        print_info "S3 bucket name not available, skipping checks"
        return
    fi
    
    if aws s3 ls "s3://$S3_BUCKET" &> /dev/null; then
        print_success "S3 bucket accessible: $S3_BUCKET"
        
        # Check for objects
        OBJECT_COUNT=$(aws s3 ls "s3://$S3_BUCKET" --recursive | wc -l)
        print_info "Objects in bucket: $OBJECT_COUNT"
    else
        print_failure "S3 bucket not accessible: $S3_BUCKET"
    fi
}

# Check DynamoDB tables
check_dynamodb() {
    print_header "Checking DynamoDB Tables"
    
    # Check beta table
    if aws dynamodb describe-table --table-name "$BETA_TABLE" &> /dev/null; then
        print_success "Beta table exists: $BETA_TABLE"
        
        BETA_COUNT=$(aws dynamodb scan --table-name "$BETA_TABLE" --select COUNT --output json | jq -r '.Count')
        print_info "Items in beta table: $BETA_COUNT"
    else
        print_failure "Beta table not found: $BETA_TABLE"
    fi
    
    # Check prod table
    if aws dynamodb describe-table --table-name "$PROD_TABLE" &> /dev/null; then
        print_success "Prod table exists: $PROD_TABLE"
        
        PROD_COUNT=$(aws dynamodb scan --table-name "$PROD_TABLE" --select COUNT --output json | jq -r '.Count')
        print_info "Items in prod table: $PROD_COUNT"
    else
        print_failure "Prod table not found: $PROD_TABLE"
    fi
}

# Check Lambda functions
check_lambda() {
    print_header "Checking Lambda Functions"
    
    # Check beta Lambda
    if aws lambda get-function --function-name rekognition-beta-handler &> /dev/null; then
        print_success "Beta Lambda function exists"
        
        STATUS=$(aws lambda get-function --function-name rekognition-beta-handler --query 'Configuration.State' --output text)
        print_info "Status: $STATUS"
    else
        print_failure "Beta Lambda function not found"
    fi
    
    # Check prod Lambda
    if aws lambda get-function --function-name rekognition-prod-handler &> /dev/null; then
        print_success "Prod Lambda function exists"
        
        STATUS=$(aws lambda get-function --function-name rekognition-prod-handler --query 'Configuration.State' --output text)
        print_info "Status: $STATUS"
    else
        print_failure "Prod Lambda function not found"
    fi
}

# Check S3 event notifications
check_s3_events() {
    print_header "Checking S3 Event Notifications"
    
    if [ -z "$S3_BUCKET" ]; then
        print_info "S3 bucket name not available, skipping checks"
        return
    fi
    
    NOTIFICATIONS=$(aws s3api get-bucket-notification-configuration --bucket "$S3_BUCKET" --output json 2>/dev/null || echo '{}')
    
    if [ "$NOTIFICATIONS" != "{}" ]; then
        LAMBDA_COUNT=$(echo "$NOTIFICATIONS" | jq -r '.LambdaFunctionConfigurations | length')
        print_success "S3 event notifications configured ($LAMBDA_COUNT Lambda triggers)"
    else
        print_failure "No S3 event notifications configured"
    fi
}

# Test local script
test_local_script() {
    print_header "Testing Local Analysis Script"
    
    if [ ! -f "$PROJECT_ROOT/scripts/analyze_image.py" ]; then
        print_failure "analyze_image.py not found"
        return
    fi
    
    print_success "analyze_image.py exists"
    
    # Check if script is executable
    if [ -x "$PROJECT_ROOT/scripts/analyze_image.py" ]; then
        print_success "Script is executable"
    else
        print_info "Making script executable..."
        chmod +x "$PROJECT_ROOT/scripts/analyze_image.py"
    fi
}

# Run summary
print_summary() {
    print_header "Test Summary"
    
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
    fi
}

# Main execution
main() {
    echo "Rekognition Pipeline Validation"
    echo "================================"
    
    check_prerequisites
    check_aws_credentials
    check_terraform
    check_s3
    check_dynamodb
    check_lambda
    check_s3_events
    test_local_script
    print_summary
}

main "$@"