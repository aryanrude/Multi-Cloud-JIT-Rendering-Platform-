data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "render_worker" {
  name_prefix = "${var.project_name}-worker-"
  image_id    = data.aws_ami.amazon_linux_2023.id

  # Default instance type — overridden per-launch by provisioner Lambda
  instance_type = "t3.medium"

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  metadata_options {
    http_tokens            = "required" # IMDSv2 enforced — no IMDSv1
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled" # Bootstrap Agent reads tags via IMDS
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type             = "one-time"
      instance_interruption_behavior = "terminate"
    }
  }

  # Bootstrap Agent — runs on every EC2 startup
  # Reads request_id + combo_id from IMDS tags (set by provisioner Lambda)
  # Checks Redis cache before fetching config, then calls back when ready
  user_data = base64encode(<<-BASH
    #!/bin/bash
    set -euo pipefail
    exec >> /var/log/bootstrap.log 2>&1

    echo "[bootstrap] starting at $(date -u)"

    # ── IMDSv2 token ──────────────────────────────────────────────────────────
    TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

    INSTANCE_ID=$(curl -sf \
      -H "X-aws-ec2-metadata-token: $TOKEN" \
      "http://169.254.169.254/latest/meta-data/instance-id")

    REGION=$(curl -sf \
      -H "X-aws-ec2-metadata-token: $TOKEN" \
      "http://169.254.169.254/latest/meta-data/placement/region")

    # Read job context from instance tags (set by provisioner Lambda)
    REQUEST_ID=$(curl -sf \
      -H "X-aws-ec2-metadata-token: $TOKEN" \
      "http://169.254.169.254/latest/meta-data/tags/instance/request_id")

    COMBO_ID=$(curl -sf \
      -H "X-aws-ec2-metadata-token: $TOKEN" \
      "http://169.254.169.254/latest/meta-data/tags/instance/combo_id")

    echo "[bootstrap] instance=$INSTANCE_ID request_id=$REQUEST_ID combo_id=$COMBO_ID"

    # ── Fetch config endpoints from SSM ───────────────────────────────────────
    CALLBACK_URL=$(aws ssm get-parameter \
      --name "${aws_ssm_parameter.callback_url.name}" \
      --region "$REGION" \
      --query "Parameter.Value" \
      --output text)

    REDIS_HOST=$(aws ssm get-parameter \
      --name "${aws_ssm_parameter.redis_host.name}" \
      --region "$REGION" \
      --query "Parameter.Value" \
      --output text)

    # ── Cache check ───────────────────────────────────────────────────────────
    dnf install -y redis6 --quiet

    CACHE_KEY="config:$COMBO_ID"
    CACHED=$(redis-cli -h "$REDIS_HOST" -p 6379 GET "$CACHE_KEY" 2>/dev/null || echo "")

    if [ -z "$CACHED" ]; then
      echo "[bootstrap] cache miss — fetching config for $COMBO_ID"
      # In production: fetch actual render engine config, plugins, scene assets
      CONFIG="render_config_for_$COMBO_ID"
      redis-cli -h "$REDIS_HOST" -p 6379 SETEX "$CACHE_KEY" 3600 "$CONFIG"
      echo "[bootstrap] config cached with 1hr TTL"
    else
      echo "[bootstrap] cache hit — skipping fetch"
    fi

    # ── Signal control plane ──────────────────────────────────────────────────
    curl -sf -X POST "$CALLBACK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"request_id\":\"$REQUEST_ID\",\"status\":\"ready\",\"instance_id\":\"$INSTANCE_ID\",\"cloud\":\"aws\"}"

    echo "[bootstrap] complete at $(date -u)"
  BASH
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "jit-renderer"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Project     = var.project_name
      Environment = var.environment
    }
  }
}
