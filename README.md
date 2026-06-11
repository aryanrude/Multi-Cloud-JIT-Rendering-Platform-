# Multi-Cloud JIT Rendering Platform — Phase 1: Control Plane

A serverless control plane that validates software/render engine compatibility,
tracks render jobs, and queues them for async VM provisioning.

## Architecture

```
User → API Gateway → Orchestrator Lambda → SQS → [Phase 2: VM provisioner]
                  ↓
              DynamoDB (compatibility matrix + job tracker)
                  ↑
         Callback Lambda ← VM reports ready
```

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5 (`terraform -version`)
- Python 3.10+ with `boto3` and `requests`

## Deploy

```bash
# 1. Init and apply
cd terraform
terraform init
terraform apply

# 2. Seed test data and run smoke tests
cd ..
pip install boto3 requests
python scripts/seed_and_test.py
```

## Project structure

```
├── terraform/
│   ├── main.tf          # Provider config
│   ├── variables.tf     # Region, env, project name
│   ├── dynamodb.tf      # Compatibility matrix + render jobs tables
│   ├── sqs.tf           # Main queue + dead letter queue
│   ├── iam.tf           # Least-privilege Lambda execution role
│   ├── lambda.tf        # Function definitions + CloudWatch log groups
│   ├── api_gateway.tf   # REST API: /provision and /callback
│   └── outputs.tf       # Endpoint URLs and table names
├── src/
│   ├── orchestrator/handler.py   # Validate → write job → enqueue
│   └── callback/handler.py      # VM ready → update job status
└── scripts/
    └── seed_and_test.py          # Seed DynamoDB + smoke test both endpoints
```

## API

### POST /provision

Submit a VM provisioning request.

```json
{
  "software":       "blender",
  "version":        "4.0",
  "render_engine":  "cycles",
  "engine_version": "4.0",
  "machine_type":   "gpu-large",
  "count":          2
}
```

Response:
```json
{
  "status":     "queued",
  "request_id": "abc-123",
  "combo_id":   "blender-4.0-cycles-4.0"
}
```

### POST /callback

Called by Bootstrap Agent on the VM when it is ready.

```json
{
  "request_id":  "abc-123",
  "status":      "ready",
  "instance_id": "i-0abc123456789def0",
  "cloud":       "aws"
}
```

## Design decisions worth explaining in interviews

**Why SQS between orchestrator and provisioner?**
Decouples validation latency from VM launch latency. Orchestrator responds in
< 100ms; actual VM launch can take 2-3 minutes. The queue also acts as a buffer
if the provisioner falls behind.

**Why a Dead Letter Queue?**
After 3 failed receive attempts, messages route to the DLQ automatically.
This prevents hot messages from looping forever and gives a clear signal that
something is wrong — check the DLQ before checking CloudWatch.

**Why `ConditionExpression` in the callback handler?**
Prevents a late-arriving duplicate callback from overwriting a terminal `ready`
state. Idempotency without a separate deduplication store.

**Why TTL on render_jobs?**
Keeps the table lean without a cron job. Jobs auto-expire after 24 hours.
For audit purposes, CloudWatch Logs retains all state transitions for 14 days.

## Next: Phase 2

Add EC2 Spot instance launch via an SQS consumer Lambda, Bootstrap Agent script,
ElastiCache for config caching, and EventBridge for spot interruption handling.
