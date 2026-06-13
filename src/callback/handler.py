import json
import os
import logging
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Attr

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb   = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

jobs_table = dynamodb.Table(os.environ['RENDER_JOBS_TABLE'])

VALID_STATUSES = {'provisioning', 'ready', 'failed'}


def _put_metric(name: str):
    try:
        cloudwatch.put_metric_data(
            Namespace='JITRenderer',
            MetricData=[{
                'MetricName': name,
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [{'Name': 'Environment', 'Value': os.environ.get('ENVIRONMENT', 'dev')}]
            }]
        )
    except Exception:
        logger.warning("Failed to emit metric %s", name)


def lambda_handler(event, context):
    logger.info("Callback received: %s", json.dumps(event))

    try:
        body = (
            json.loads(event['body'])
            if isinstance(event.get('body'), str)
            else event
        )

        request_id  = body.get('request_id')
        status      = body.get('status', 'ready')
        instance_id = body.get('instance_id', 'unknown')
        cloud       = body.get('cloud', 'unknown')
        error_msg   = body.get('error')

        if not request_id:
            return _error(400, "Missing request_id")

        if status not in VALID_STATUSES:
            return _error(400, f"Invalid status: {status}")

        now = datetime.now(timezone.utc).isoformat()

        update_expr = "SET #s = :status, instance_id = :iid, cloud = :cloud, updated_at = :ts"
        expr_values = {
            ':status': status,
            ':iid':    instance_id,
            ':cloud':  cloud,
            ':ts':     now,
        }

        if status == 'ready':
            update_expr += ", ready_at = :ts"
        elif status == 'failed' and error_msg:
            update_expr += ", error_message = :err"
            expr_values[':err'] = error_msg

        jobs_table.update_item(
            Key={'request_id': request_id},
            UpdateExpression=update_expr,
            ConditionExpression=Attr('status').ne('ready'),
            ExpressionAttributeNames={'#s': 'status'},
            ExpressionAttributeValues=expr_values,
        )

        # Emit metric only on meaningful state transitions
        if status == 'ready':
            _put_metric('JobsCompleted')
        elif status == 'failed':
            _put_metric('JobsFailed')

        logger.info("Updated request_id=%s status=%s instance=%s cloud=%s",
                    request_id, status, instance_id, cloud)

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Status updated', 'request_id': request_id, 'status': status})
        }

    except jobs_table.meta.client.exceptions.ConditionalCheckFailedException:
        logger.warning("Conditional check failed for request_id=%s — already ready", body.get('request_id'))
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Already in terminal state'})
        }

    except Exception:
        logger.exception("Unhandled error in callback handler")
        return _error(500, "Internal server error")


def _error(status: int, message: str) -> dict:
    return {
        'statusCode': status,
        'body': json.dumps({'error': message})
    }
