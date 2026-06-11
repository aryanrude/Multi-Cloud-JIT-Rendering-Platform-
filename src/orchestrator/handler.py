import json
import os
import logging
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

compat_table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
jobs_table   = dynamodb.Table(os.environ['RENDER_JOBS_TABLE'])

REQUIRED_FIELDS = ['software', 'version', 'render_engine', 'engine_version']
MAX_COUNT = 50


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    try:
        body = (
            json.loads(event['body'])
            if isinstance(event.get('body'), str)
            else event
        )

        # Validate required fields before touching DynamoDB
        missing = [f for f in REQUIRED_FIELDS if not body.get(f)]
        if missing:
            return _error(400, f"Missing required fields: {missing}")

        software       = body['software']
        version        = body['version']
        render_engine  = body['render_engine']
        engine_version = body['engine_version']
        machine_type   = body.get('machine_type', 'default')
        count          = min(int(body.get('count', 1)), MAX_COUNT)

        # Step 1: validate against compatibility matrix
        combo_id = f"{software}-{version}-{render_engine}-{engine_version}"
        resp = compat_table.get_item(Key={'combo_id': combo_id})

        if 'Item' not in resp:
            return _error(400, f"Invalid combination: {combo_id}")

        request_id = context.aws_request_id
        now        = datetime.now(timezone.utc).isoformat()
        ttl        = int(datetime.now(timezone.utc).timestamp()) + 86400  # 24h

        # Step 2: write initial job record so we can track it immediately
        jobs_table.put_item(Item={
            'request_id':  request_id,
            'status':      'queued',
            'combo_id':    combo_id,
            'machine_type': machine_type,
            'count':       count,
            'queued_at':   now,
            'ttl':         ttl,
        })

        # Step 3: enqueue for async processing
        sqs.send_message(
            QueueUrl=os.environ['QUEUE_URL'],
            MessageBody=json.dumps({
                'request_id':   request_id,
                'combo_id':     combo_id,
                'software':     software,
                'version':      version,
                'render_engine': render_engine,
                'engine_version': engine_version,
                'machine_type': machine_type,
                'count':        count,
                'queued_at':    now,
            })
        )

        logger.info("Queued request_id=%s combo=%s", request_id, combo_id)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'status':     'queued',
                'request_id': request_id,
                'combo_id':   combo_id,
            })
        }

    except Exception:
        logger.exception("Unhandled error in orchestrator")
        return _error(500, "Internal server error")


def _error(status: int, message: str) -> dict:
    return {
        'statusCode': status,
        'body': json.dumps({'error': message})
    }
