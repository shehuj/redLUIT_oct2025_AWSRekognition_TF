# IAM role for Lambda execution
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-rekognition-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-rekognition-lambda-role"
    Environment = var.environment
  }
}

# Policy for S3 access
resource "aws_iam_role_policy" "s3_policy" {
  name = "${var.project_name}-lambda-s3-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketWebsite",
          "s3:GetBucketWebsite",
          "s3:PutBucketTagging",
          "s3:GetBucketTagging",
          "s3:PutBucketAcl",
          "s3:GetBucketAcl"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Policy for DynamoDB access
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "${var.project_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:ListTables"
        ]
        Resource = [
          var.dynamodb_table_arns.beta,
          var.dynamodb_table_arns.prod,
          "${var.dynamodb_table_arns.beta}/index/*",
          "${var.dynamodb_table_arns.prod}/index/*"
        ]
      }
    ]
  })
}

# Policy for Rekognition access
resource "aws_iam_role_policy" "rekognition_policy" {
  name = "${var.project_name}-lambda-rekognition-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels",
          "rekognition:DetectText",
          "rekognition:DetectFaces",
          "rekognition:RecognizeCelebrities",
          "rekognition:DetectModerationLabels",
          "rekognition:DetectProtectiveEquipment",
          "rekognition:DetectTextModeration",
          "rekognition:IndexFaces",
          "rekognition:SearchFaces",
          "rekognition:SearchFacesByImage",
          "rekognition:DeleteFaces",
          "rekognition:ListFaces",
          "rekognition:ListCollections"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Optional: IAM user for GitHub Actions (if not using OIDC)
resource "aws_iam_user" "github_actions" {
  name = "${var.project_name}-github-actions-user"

  tags = {
    Name        = "${var.project_name}-github-actions-user"
    Environment = var.environment
  }
}

# Policy for GitHub Actions user
resource "aws_iam_user_policy" "github_actions_policy" {
  name = "${var.project_name}-github-actions-policy"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          var.dynamodb_table_arns.beta,
          var.dynamodb_table_arns.prod
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels"
        ]
        Resource = "*"
      }
    ]
  })
}

# Access key for GitHub Actions (store securely!)
resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}