import json
import os
import logging

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
ec2      = boto3.client('ec2')

jobs_table = dynamodb.Table(os.environ['RENDER_JOBS_TABLE'])

# Maps machine_type from the request to actual EC2 instance types
# t3.medium for dev/testing (no GPU, cheap). Use g4dn for real renders.
MACHINE_TYPE_MAP = {
    'gpu-large':  'g4dn.xlarge',   # 4 vCPU, 16GB RAM, T4 GPU
    'gpu-small':  'g4dn.large',    # 2 vCPU, 8GB RAM, T4 GPU
    'cpu-large':  'c5.4xlarge',    # 16 vCPU, 32GB RAM, no GPU
    'cpu-small':  'c5.xlarge',     # 4 vCPU, 8GB RAM, no GPU
    'default':    't3.medium',     # dev/testing only
}


def lambda_handler(event, context):
    """
    Triggered by SQS. Processes one job at a time (batch_size=1).
    Re-raising on failure keeps the message visible for retry → DLQ.
    """
    for record in event['Records']:
        try:
            process_job(record)
        except Exception:
            logger.exception("Failed to process SQS record %s", record['messageId'])
            raise  # triggers retry → DLQ after maxReceiveCount


def process_job(record: dict):
    body       = json.loads(record['body'])
    request_id = body['request_id']
    combo_id   = body.get('combo_id', '')
    is_requeue = body.get('requeue', False)

    logger.info(
        "Processing request_id=%s combo=%s requeue=%s",
        request_id, combo_id, is_requeue
    )

    # On requeue (post-interruption), fetch original machine_type from DynamoDB
    if is_requeue:
        resp = jobs_table.get_item(Key={'request_id': request_id})
        job  = resp.get('Item', {})
        machine_type = job.get('machine_type', 'default')
        count        = int(job.get('count', 1))
        combo_id     = job.get('combo_id', combo_id)
    else:
        machine_type = body.get('machine_type', 'default')
        count        = min(int(body.get('count', 1)), 50)

    instance_type = MACHINE_TYPE_MAP.get(machine_type, 't3.medium')

    # Mark job as provisioning
    jobs_table.update_item(
        Key={'request_id': request_id},
        UpdateExpression="SET #s = :status, instance_type = :itype",
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={
            ':status': 'provisioning',
            ':itype':  instance_type,
        }
    )

    # Launch EC2 Spot instance(s)
    resp = ec2.run_instances(
        MinCount=count,
        MaxCount=count,
        LaunchTemplate={
            'LaunchTemplateId': os.environ['LAUNCH_TEMPLATE_ID'],
            'Version':          '$Latest',
        },
        InstanceType=instance_type,
        TagSpecifications=[{
            'ResourceType': 'instance',
            'Tags': [
                {'Key': 'request_id', 'Value': request_id},
                {'Key': 'combo_id',   'Value': combo_id},
                {'Key': 'Name',       'Value': f'jit-worker-{combo_id[:20]}'},
            ]
        }]
    )

    instance_ids = [i['InstanceId'] for i in resp['Instances']]
    logger.info(
        "Launched %d × %s for request_id=%s → %s",
        count, instance_type, request_id, instance_ids
    )
