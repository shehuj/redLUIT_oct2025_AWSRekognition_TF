import json
import boto3
import os
from datetime import datetime
from urllib.parse import unquote_plus
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rekognition = boto3.client('rekognition')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Get environment variables
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'beta')
MAX_LABELS = int(os.environ.get('MAX_LABELS', '10'))
MIN_CONFIDENCE = float(os.environ.get('MIN_CONFIDENCE', '70.0'))

def lambda_handler(event, context):
    """
    Lambda handler triggered by S3 events.
    Processes images using Amazon Rekognition and stores results in DynamoDB.
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Process each record in the event
        for record in event['Records']:
            # Extract S3 bucket and key information
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing image: {key} from bucket: {bucket}")
            
            # Validate file type
            if not key.lower().endswith(('.jpg', '.jpeg', '.png')):
                logger.warning(f"Skipping non-image file: {key}")
                continue
            
            # Call Rekognition to detect labels
            try:
                response = rekognition.detect_labels(
                    Image={
                        'S3Object': {
                            'Bucket': bucket,
                            'Name': key
                        }
                    },
                    MaxLabels=MAX_LABELS,
                    MinConfidence=MIN_CONFIDENCE
                )
                
                logger.info(f"Rekognition response: {json.dumps(response, default=str)}")
                
            except Exception as e:
                logger.error(f"Error calling Rekognition: {str(e)}")
                raise
            
            # Extract and format labels
            labels = []
            for label in response['Labels']:
                labels.append({
                    'Name': label['Name'],
                    'Confidence': round(label['Confidence'], 2)
                })
            
            # Extract branch from the key path
            # Format: rekognition-input/beta/filename.jpg or rekognition-input/prod/filename.jpg
            path_parts = key.split('/')
            branch = path_parts[1] if len(path_parts) > 1 else ENVIRONMENT
            
            # Prepare DynamoDB item
            timestamp = datetime.utcnow().isoformat() + 'Z'
            item = {
                'filename': key,
                'labels': labels,
                'timestamp': timestamp,
                'branch': branch,
                'environment': ENVIRONMENT,
                'label_count': len(labels),
                'rekognition_request_id': response['ResponseMetadata']['RequestId']
            }
            
            # Add TTL (90 days from now)
            ttl = int(datetime.utcnow().timestamp()) + (90 * 24 * 60 * 60)
            item['ttl'] = ttl
            
            logger.info(f"Writing to DynamoDB table: {DYNAMODB_TABLE}")
            logger.info(f"Item: {json.dumps(item, default=str)}")
            
            # Store results in DynamoDB
            try:
                table = dynamodb.Table(DYNAMODB_TABLE)
                table.put_item(Item=item)
                logger.info(f"Successfully stored results for {key}")
                
            except Exception as e:
                logger.error(f"Error writing to DynamoDB: {str(e)}")
                raise
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully processed images',
                'processed_count': len(event['Records'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing images',
                'error': str(e)
            })
        }


def get_results_by_branch(table_name, branch_name, limit=10):
    """
    Helper function to query results by branch.
    Can be used for validation or reporting.
    """
    table = dynamodb.Table(table_name)
    
    response = table.query(
        IndexName='BranchIndex',
        KeyConditionExpression='branch = :branch',
        ExpressionAttributeValues={
            ':branch': branch_name
        },
        Limit=limit,
        ScanIndexForward=False  # Most recent first
    )
    
    return response['Items']