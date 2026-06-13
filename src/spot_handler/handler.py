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
cloudwatch = boto3.client('cloudwatch')

jobs_table = dynamodb.Table(os.environ['RENDER_JOBS_TABLE'])


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
    logger.info("Spot interruption event: %s", json.dumps(event))

    instance_id = event.get('detail', {}).get('instance-id')
    if not instance_id:
        logger.error("No instance-id in event detail")
        return

    request_id = get_instance_tag(instance_id, 'request_id')
    combo_id   = get_instance_tag(instance_id, 'combo_id')

    if not request_id:
        logger.info("Instance %s has no request_id tag — not managed by us", instance_id)
        return

    logger.info("Spot interruption: instance=%s request_id=%s", instance_id, request_id)

    now = datetime.now(timezone.utc).isoformat()

    jobs_table.update_item(
        Key={'request_id': request_id},
        UpdateExpression="SET #s = :status, interrupted_at = :ts, interrupted_instance = :iid",
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={
            ':status': 'interrupted',
            ':ts':     now,
            ':iid':    instance_id,
        }
    )

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

    # Emit metric — visible in Grafana, triggers alerting if spikes
    _put_metric('SpotInterruptions')

    logger.info("Requeued request_id=%s after spot interruption", request_id)


def get_instance_tag(instance_id: str, key: str) -> Optional[str]:
    try:
        resp = ec2_client.describe_instances(InstanceIds=[instance_id])
        tags = resp['Reservations'][0]['Instances'][0].get('Tags', [])
        for tag in tags:
            if tag['Key'] == key:
                return tag['Value']
    except Exception:
        logger.exception("Failed to get tags for instance %s", instance_id)
    return None
