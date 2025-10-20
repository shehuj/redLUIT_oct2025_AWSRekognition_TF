#!/usr/bin/env python3
"""
Direct image analysis script for Amazon Rekognition.
This script uploads images to S3 and calls Rekognition directly (foundational implementation).
"""

import boto3
import os
import sys
import json
from datetime import datetime
from pathlib import Path

def analyze_image(image_path, environment='beta'):
    """
    Upload image to S3, analyze with Rekognition, and store results in DynamoDB.
    
    Args:
        image_path: Path to the image file
        environment: 'beta' or 'prod'
    """
    # Get configuration from environment variables
    s3_bucket = os.environ.get('S3_BUCKET')
    dynamodb_table = os.environ.get('DYNAMODB_TABLE')
    aws_region = os.environ.get('AWS_REGION', 'us-east-1')
    
    if not s3_bucket or not dynamodb_table:
        print("Error: S3_BUCKET and DYNAMODB_TABLE environment variables must be set")
        sys.exit(1)
    
    # Validate image file
    if not os.path.exists(image_path):
        print(f"Error: Image file not found: {image_path}")
        sys.exit(1)
    
    filename = os.path.basename(image_path)
    
    # Validate image extension
    valid_extensions = ['.jpg', '.jpeg', '.png', 'pdf']
    if not any(filename.lower().endswith(ext) for ext in valid_extensions):
        print(f"Error: Invalid file type. Must be .jpg, .jpeg, or .png")
        sys.exit(1)
    
    # Initialize AWS clients
    s3_client = boto3.client('s3', region_name=aws_region)
    rekognition_client = boto3.client('rekognition', region_name=aws_region)
    dynamodb = boto3.resource('dynamodb', region_name=aws_region)
    
    print(f"Processing image: {filename}")
    print(f"Environment: {environment}")
    print(f"S3 Bucket: {s3_bucket}")
    print(f"DynamoDB Table: {dynamodb_table}")
    
    # Upload to S3
    s3_key = f"rekognition-input/{filename}"
    
    try:
        print(f"\n1. Uploading to S3: s3://{s3_bucket}/{s3_key}")
        s3_client.upload_file(
            image_path,
            s3_bucket,
            s3_key,
            ExtraArgs={
                'Metadata': {
                    'environment': environment,
                    'uploaded-by': 'analyze_image_script'
                }
            }
        )
        print("Upload successful")
    except Exception as e:
        print(f"Error uploading to S3: {str(e)}")
        sys.exit(1)
    
    # Call Rekognition
    try:
        print(f"\n2. Analyzing image with Rekognition...")
        response = rekognition_client.detect_labels(
            Image={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            MaxLabels=10,
            MinConfidence=70.0
        )
        print(f"Found {len(response['Labels'])} labels")
    except Exception as e:
        print(f"Error calling Rekognition: {str(e)}")
        sys.exit(1)
    
    # Format labels
    labels = []
    for label in response['Labels']:
        labels.append({
            'Name': label['Name'],
            'Confidence': round(label['Confidence'], 2)
        })
    
    # Display results
    print(f"\n3. Detected Labels:")
    for label in labels:
        print(f"   - {label['Name']}: {label['Confidence']}%")
    
    # Prepare DynamoDB item
    timestamp = datetime.utcnow().isoformat() + 'Z'
    
    # Get git branch if available
    try:
        import subprocess
        branch = subprocess.check_output(
            ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
            stderr=subprocess.DEVNULL
        ).decode('utf-8').strip()
    except:
        branch = environment
    
    item = {
        'filename': s3_key,
        'labels': labels,
        'timestamp': timestamp,
        'branch': branch,
        'environment': environment,
        'label_count': len(labels),
        'analysis_method': 'direct_script'
    }
    
    # Store in DynamoDB
    try:
        print(f"\n4. Storing results in DynamoDB table: {dynamodb_table}")
        table = dynamodb.Table(dynamodb_table)
        table.put_item(Item=item)
        print("Results stored successfully")
    except Exception as e:
        print(f"Error writing to DynamoDB: {str(e)}")
        sys.exit(1)
    
    # Print summary
    print(f"\n{'='*60}")
    print("ANALYSIS COMPLETE")
    print(f"{'='*60}")
    print(json.dumps(item, indent=2))
    print(f"{'='*60}")
    
    return item


def main():
    """Main entry point for the script."""
    if len(sys.argv) < 2:
        print("Usage: python analyze_image.py <image_path> [environment]")
        print("Example: python analyze_image.py images/balloon.jpg beta")
        sys.exit(1)
    
    image_path = sys.argv[1]
    environment = sys.argv[2] if len(sys.argv) > 2 else 'beta'
    
    if environment not in ['beta', 'prod']:
        print("Error: Environment must be 'beta' or 'prod'")
        sys.exit(1)
    
    # Set the appropriate DynamoDB table based on environment
    if environment == 'beta':
        os.environ['DYNAMODB_TABLE'] = os.environ.get('DYNAMODB_TABLE_BETA', 'beta_results')
    else:
        os.environ['DYNAMODB_TABLE'] = os.environ.get('DYNAMODB_TABLE_PROD', 'prod_results')
    
    analyze_image(image_path, environment)


if __name__ == '__main__':
    main()