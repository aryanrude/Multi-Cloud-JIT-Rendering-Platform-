import json
import os
import logging
from datetime import datetime, timezone
from typing import Optional

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb   = boto3.resource('dynamodb')
sqs        = boto3.client('sqs')
ec2_client = boto3.client('ec2')

jobs_table = dynamodb.Table(os.environ['RENDER_JOBS_TABLE'])


def lambda_handler(event, context):
    """
    Triggered by EventBridge when AWS sends an EC2 Spot Interruption Warning.
    AWS gives ~2 minutes notice before terminating the instance.

    Flow:
      1. Get the interrupted instance's tags to find our request_id
      2. Mark job as 'interrupted' in DynamoDB
      3. Requeue to SQS so a new instance gets launched automatically
    """
    logger.info("Spot interruption event: %s", json.dumps(event))

    instance_id = event.get('detail', {}).get('instance-id')
    if not instance_id:
        logger.error("No instance-id in event — nothing to do")
        return

    request_id = get_instance_tag(instance_id, 'request_id')
    combo_id   = get_instance_tag(instance_id, 'combo_id')

    if not request_id:
        logger.info(
            "Instance %s has no request_id tag — not managed by us, ignoring",
            instance_id
        )
        return

    logger.info(
        "Spot interruption: instance=%s request_id=%s combo=%s",
        instance_id, request_id, combo_id
    )

    now = datetime.now(timezone.utc).isoformat()

    # Step 1: mark interrupted in DynamoDB
    jobs_table.update_item(
        Key={'request_id': request_id},
        UpdateExpression=(
            "SET #s = :status, interrupted_at = :ts, interrupted_instance = :iid"
        ),
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={
            ':status': 'interrupted',
            ':ts':     now,
            ':iid':    instance_id,
        }
    )

    # Step 2: requeue — provisioner Lambda will re-fetch machine_type from DB
    sqs.send_message(
        QueueUrl=os.environ['QUEUE_URL'],
        MessageBody=json.dumps({
            'request_id':           request_id,
            'combo_id':             combo_id or '',
            'requeue':              True,
            'interrupted_instance': instance_id,
            'queued_at':            now,
        })
    )

    logger.info("Requeued request_id=%s — new instance will be launched", request_id)


def get_instance_tag(instance_id: str, key: str) -> Optional[str]:
    """Fetch a tag value from an EC2 instance. Returns None if not found."""
    try:
        resp = ec2_client.describe_instances(InstanceIds=[instance_id])
        tags = resp['Reservations'][0]['Instances'][0].get('Tags', [])
        for tag in tags:
            if tag['Key'] == key:
                return tag['Value']
    except Exception:
        logger.exception("Failed to get tags for instance %s", instance_id)
    return None
