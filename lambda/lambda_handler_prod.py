import boto3
import json
import os
from datetime import datetime
from urllib.parse import unquote_plus

# Initialize AWS clients
rekognition_client = boto3.client('rekognition')
dynamodb = boto3.resource('dynamodb')
bucket_name = os.environ.get('S3_BUCKET', 'pixel-learning-rekognition-images-4sfnas3n')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE_PROD', 'beta_results')

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
    expected_prefix = 'rekognition-input/prod/'
    if not key.startswith(expected_prefix):
        error_msg = f"Invalid key prefix. Expected '{expected_prefix}', got: {key}"
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }

    # Validate image extension
    valid_extensions = ('.jpg', '.jpeg', '.png', '.pdf', '.heic')
    if not key.lower().endswith(valid_extensions):
        error_msg = f"Invalid file type. Must be one of {valid_extensions}, got: {key}"
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }

    # Call Rekognition to detect labels
    try:
        print("Calling Amazon Rekognition...")
        response = rekognition_client.detect_labels(
            Image={'S3Object': {'Bucket': bucket, 'Name': key}},
            MaxLabels=10,
            MinConfidence=50.0
        )
        label_count = len(response.get('Labels', []))
        print(f"Rekognition found {label_count} label(s)")
    except Exception as e:
        error_msg = f"Error calling Rekognition: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }

    # Format labels for storage
    labels = [
        {'Name': label['Name'], 'Confidence': round(label['Confidence'], 2)}
        for label in response.get('Labels', [])
    ]

    # Print detected labels
    print("Detected labels:")
    for lbl in labels:
        print(f"  - {lbl['Name']}: {lbl['Confidence']}%")

    # Prepare DynamoDB item
    timestamp = datetime.timezone().isoformat(timespec='seconds') + 'Z'
    item = {
        'filename': key,
        'timestamp': timestamp,
        'labels': labels,
        'label_count': label_count,
        'branch': 'prod',
        'environment': 'prod',
        'analysis_method': 'lambda_s3_trigger',
        's3_bucket': bucket
    }

    # Write results to DynamoDB
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
    print("Lambda execution completed successfully")
    return result
# End of lambda_handler_beta.py
print("Lambda function for prod environment loaded.")