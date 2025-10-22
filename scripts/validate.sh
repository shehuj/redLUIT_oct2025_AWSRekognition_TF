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

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    print_info "Detected OS: $OS"
}

# Install missing prerequisites
install_prerequisite() {
    local pkg=$1
    print_info "Installing $pkg..."
    case "$OS" in
        amzn|amazon)
            sudo yum install -y "$pkg"
            ;;
        ubuntu|debian)
            sudo apt-get update -y && sudo apt-get install -y "$pkg"
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew install "$pkg"
            else
                print_failure "Homebrew not found. Please install Homebrew to continue."
                exit 1
            fi
            ;;
        *)
            print_failure "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Install AWS CLI v2 (custom install logic)
install_aws_cli() {
    print_info "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    detect_os

    if command -v aws &> /dev/null; then
        print_success "AWS CLI installed"
    else
        print_failure "AWS CLI not found"
        install_aws_cli
    fi
    
    if command -v terraform &> /dev/null; then
        print_success "Terraform installed"
    else
        print_failure "Terraform not found"
        install_prerequisite terraform || {
            print_info "Installing Terraform manually..."
            wget -q https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
            unzip terraform_1.7.5_linux_amd64.zip
            sudo mv terraform /usr/local/bin/
            rm terraform_1.7.5_linux_amd64.zip
        }
    fi
    
    if command -v python3 &> /dev/null; then
        print_success "Python 3 installed"
    else
        print_failure "Python 3 not found"
        install_prerequisite python3
    fi
    
    if command -v jq &> /dev/null; then
        print_success "jq installed"
    else
        print_info "jq not found — installing..."
        install_prerequisite jq
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
    
    if terraform output &> /dev/null; then
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
        BETA_TABLE=$(terraform output -raw dynamodb_beta_table_name 2>/dev/null || echo "beta_results")
        PROD_TABLE=$(terraform output -raw dynamodb_prod_table_name 2>/null || echo "prod_results")
        
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
        OBJECT_COUNT=$(aws s3 ls "s3://$S3_BUCKET" --recursive | wc -l)
        print_info "Objects in bucket: $OBJECT_COUNT"
    else
        print_failure "S3 bucket not accessible: $S3_BUCKET"
    fi
}

# Check DynamoDB tables
check_dynamodb() {
    print_header "Checking DynamoDB Tables"

    # Beta table
    if aws dynamodb describe-table --table-name "$BETA_TABLE" &> /dev/null; then
        print_success "Beta table exists: $BETA_TABLE"

        # Provide partition + sort key for GetItem
        KEY_FILENAME=["s3.jpg", "dna.JPG, "luit-4.pdf"][0] 
        KEY_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

        print_info "Getting item from beta table using key: filename=$KEY_FILENAME, timestamp=$KEY_TIMESTAMP"
        if aws dynamodb get-item \
             --table-name "$DYNAMO_TABLE_BETA" \
             --key "{\"filename\":{\"S\":\"$KEY_FILENAME\"},\"timestamp\":{\"S\":\"$KEY_TIMESTAMP\"}}" &> /dev/null; then
            print_success "Successfully retrieved an item from beta table"
        else
            print_failure "Failed to retrieve item from beta table with provided key"
        fi

        BETA_COUNT=$(aws dynamodb scan --table-name "$DYNAMO_TABLE_BETA" --select COUNT --output json | jq -r '.Count')
        print_info "Items in beta table: $BETA_COUNT"
    else
        print_failure "Beta table not found: $DYNAMO_TABLE_BETA"
    fi

    # Prod table
    if aws dynamodb describe-table --table-name "$DYNAMO_TABLE_PROD" &> /dev/null; then
        print_success "Prod table exists: $DYNAMO_TABLE_PROD"

        # Provide partition + sort key for GetItem (you may adjust values)
        KEY_FILENAME="example-file.jpg"
        KEY_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

        print_info "Getting item from prod table using key: filename=$KEY_FILENAME, timestamp=$KEY_TIMESTAMP"
        if aws dynamodb get-item \
             --table-name "$PROD_TABLE" \
             --key "{\"filename\":{\"S\":\"$KEY_FILENAME\"},\"timestamp\":{\"S\":\"$KEY_TIMESTAMP\"}}" &> /dev/null; then
            print_success "Successfully retrieved an item from prod table"
        else
            print_failure "Failed to retrieve item from prod table with provided key"
        fi

        PROD_COUNT=$(aws dynamodb scan --table-name "$DYNAMO_TABLE_PROD" --select COUNT --output json | jq -r '.Count')
        print_info "Items in prod table: $PROD_COUNT"
    else
        print_failure "Prod table not found: $DYNAMO_TABLE_PROD"
    fi
}

# Check Lambda functions
check_lambda() {
    print_header "Checking Lambda Functions"

    if aws lambda get-function --function-name rekognition-beta-handler &> /dev/null; then
        print_success "Beta Lambda function exists"
        STATUS=$(aws lambda get-function --function-name rekognition-beta-handler --query 'Configuration.State' --output text)
        print_info "Status: $STATUS"
    else
        print_failure "Beta Lambda function not found"
    fi

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