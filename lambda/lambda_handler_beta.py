"""
Lambda function for Beta environment image processing.
Triggered by S3 uploads to rekognition-input/beta/
"""

import boto3
import json
import os
from datetime import datetime
from urllib.parse import unquote_plus

# Initialize AWS clients
rekognition_client = boto3.client('rekognition')
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')
bucket_name = os.environ.get('S3_BUCKET', 'pixel-learning-rekognition-images-7bgawsey')

# Get DynamoDB table name from environment variable
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'beta_results')


def lambda_handler(event, context):
    """
    Lambda handler triggered by S3 event for beta environment.
    
    Args:
        event: S3 event notification
        context: Lambda context
    """
    print(f"Event received: {json.dumps(event)}")
    
    # Extract S3 bucket and key from event
    try:
        record = event['Records'][0]
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing image from S3: s3://{bucket}/{key}")
    except (KeyError, IndexError) as e:
        error_msg = f"Error parsing S3 event: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }
    
    # Validate file is in the correct prefix
    if not key.startswith('rekognition-input/beta/'):
        error_msg = f"Invalid key prefix. Expected 'rekognition-input/beta/', got: {key}"
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }
    
    # Validate image extension
    valid_extensions = ('.jpg', '.jpeg', '.png')
    if not key.lower().endswith(valid_extensions):
        error_msg = f"Invalid file type. Must be .jpg, .jpeg, or .png"
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }
    
    # Call Rekognition to detect labels
    try:
        print("Calling Amazon Rekognition...")
        response = rekognition_client.detect_labels(
            Image={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            },
            MaxLabels=10,
            MinConfidence=70.0
        )
        
        label_count = len(response['Labels'])
        print(f"Rekognition found {label_count} labels")
        
    except Exception as e:
        error_msg = f"Error calling Rekognition: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }
    
    # Format labels for storage
    labels = []
    for label in response['Labels']:
        labels.append({
            'Name': label['Name'],
            'Confidence': round(label['Confidence'], 2)
        })
    
    # Print detected labels
    print("Detected labels:")
    for label in labels:
        print(f"  - {label['Name']}: {label['Confidence']}%")
    
    # Prepare DynamoDB item
    timestamp = datetime.utcnow().isoformat() + 'Z'
    
    item = {
        'filename': key,
        'labels': labels,
        'timestamp': timestamp,
        'branch': 'beta',
        'environment': 'beta',
        'label_count': label_count,
        'analysis_method': 'lambda_s3_trigger',
        's3_bucket': bucket
    }
    
    # Store results in DynamoDB
    try:
        print(f"Writing results to DynamoDB table: {DYNAMODB_TABLE}")
        table = dynamodb.Table(DYNAMODB_TABLE)
        table.put_item(Item=item)
        print("Results stored successfully in DynamoDB")
        
    except Exception as e:
        error_msg = f"Error writing to DynamoDB: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }
    
    # Return success response
    result = {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Image processed successfully',
            'filename': key,
            'label_count': label_count,
            'environment': 'beta',
            'timestamp': timestamp
        })
    }
    
    print(f"Lambda execution completed successfully")
    return result