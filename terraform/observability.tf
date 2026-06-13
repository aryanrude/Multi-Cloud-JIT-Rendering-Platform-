# ── Security group ────────────────────────────────────────────────────────────

resource "aws_security_group" "observability" {
  name        = "${var.project_name}-observability-${var.environment}"
  description = "Grafana and Prometheus observability server"
  vpc_id      = data.aws_vpc.default.id

  # Grafana — open to internet for portfolio demo
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus — internal only
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-observability-${var.environment}" }
}

# ── EC2 instance ──────────────────────────────────────────────────────────────

resource "aws_instance" "observability" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small" # 2GB RAM — enough for Grafana + Prometheus
  iam_instance_profile   = aws_iam_instance_profile.observability.name
  vpc_security_group_ids = [aws_security_group.observability.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = base64encode(<<-BASH
    #!/bin/bash
    exec > /var/log/observability-setup.log 2>&1
    echo "[setup] starting at $(date -u)"

    # ── Grafana ───────────────────────────────────────────────────────────────
    cat > /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

    dnf install -y grafana
    echo "[setup] grafana installed"

    # ── Prometheus ────────────────────────────────────────────────────────────
    PROM_VERSION="2.51.0"
    curl -sLO https://github.com/prometheus/prometheus/releases/download/v$${PROM_VERSION}/prometheus-$${PROM_VERSION}.linux-amd64.tar.gz
    tar xf prometheus-$${PROM_VERSION}.linux-amd64.tar.gz
    cp prometheus-$${PROM_VERSION}.linux-amd64/prometheus /usr/local/bin/
    cp prometheus-$${PROM_VERSION}.linux-amd64/promtool /usr/local/bin/
    mkdir -p /etc/prometheus /var/lib/prometheus
    echo "[setup] prometheus installed"

    # ── Prometheus config ─────────────────────────────────────────────────────
    cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 60s
  evaluation_interval: 60s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

    # ── Prometheus systemd service ────────────────────────────────────────────
    cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    chown -R nobody:nobody /var/lib/prometheus

    # ── Grafana datasource provisioning ───────────────────────────────────────
    mkdir -p /etc/grafana/provisioning/datasources
    cat > /etc/grafana/provisioning/datasources/sources.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: CloudWatch
    type: cloudwatch
    uid: cloudwatch
    jsonData:
      authType: default
      defaultRegion: ${var.aws_region}
    isDefault: false

  - name: Prometheus
    type: prometheus
    uid: prometheus
    url: http://localhost:9090
    isDefault: true
EOF

    # ── Grafana dashboard provisioning ────────────────────────────────────────
    mkdir -p /etc/grafana/provisioning/dashboards
    cat > /etc/grafana/provisioning/dashboards/default.yaml << 'EOF'
apiVersion: 1
providers:
  - name: JITRenderer
    folder: JIT Renderer
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

    mkdir -p /var/lib/grafana/dashboards

    # ── Write dashboard JSON ──────────────────────────────────────────────────
    python3 << 'PYEOF'
import json

dashboard = {
  "title": "JIT Renderer Platform",
  "uid": "jit-renderer-overview",
  "refresh": "30s",
  "schemaVersion": 38,
  "tags": ["jit-renderer"],
  "time": {"from": "now-3h", "to": "now"},
  "panels": [
    {
      "id": 1, "type": "timeseries",
      "title": "Jobs Queued (SQS)",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
      "targets": [{
        "refId": "A", "queryMode": "Metrics",
        "namespace": "AWS/SQS", "metricName": "NumberOfMessagesSent",
        "dimensions": {"QueueName": "jit-renderer-jobs-dev"},
        "statistic": "Sum", "period": "60", "region": "default"
      }]
    },
    {
      "id": 2, "type": "timeseries",
      "title": "Queue Depth",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
      "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
      "targets": [{
        "refId": "A", "queryMode": "Metrics",
        "namespace": "AWS/SQS",
        "metricName": "ApproximateNumberOfMessagesVisible",
        "dimensions": {"QueueName": "jit-renderer-jobs-dev"},
        "statistic": "Maximum", "period": "60", "region": "default"
      }]
    },
    {
      "id": 3, "type": "timeseries",
      "title": "Lambda Invocations",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
      "targets": [
        {
          "refId": "A", "alias": "Orchestrator", "queryMode": "Metrics",
          "namespace": "AWS/Lambda", "metricName": "Invocations",
          "dimensions": {"FunctionName": "jit-renderer-orchestrator-dev"},
          "statistic": "Sum", "period": "60", "region": "default"
        },
        {
          "refId": "B", "alias": "Provisioner", "queryMode": "Metrics",
          "namespace": "AWS/Lambda", "metricName": "Invocations",
          "dimensions": {"FunctionName": "jit-renderer-provisioner-dev"},
          "statistic": "Sum", "period": "60", "region": "default"
        },
        {
          "refId": "C", "alias": "Callback", "queryMode": "Metrics",
          "namespace": "AWS/Lambda", "metricName": "Invocations",
          "dimensions": {"FunctionName": "jit-renderer-callback-dev"},
          "statistic": "Sum", "period": "60", "region": "default"
        }
      ]
    },
    {
      "id": 4, "type": "timeseries",
      "title": "Lambda Errors",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
      "targets": [
        {
          "refId": "A", "alias": "Orchestrator Errors", "queryMode": "Metrics",
          "namespace": "AWS/Lambda", "metricName": "Errors",
          "dimensions": {"FunctionName": "jit-renderer-orchestrator-dev"},
          "statistic": "Sum", "period": "60", "region": "default"
        },
        {
          "refId": "B", "alias": "Provisioner Errors", "queryMode": "Metrics",
          "namespace": "AWS/Lambda", "metricName": "Errors",
          "dimensions": {"FunctionName": "jit-renderer-provisioner-dev"},
          "statistic": "Sum", "period": "60", "region": "default"
        }
      ]
    },
    {
      "id": 5, "type": "timeseries",
      "title": "Custom Metrics - Job Lifecycle",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
      "targets": [
        {
          "refId": "A", "alias": "Jobs Queued", "queryMode": "Metrics",
          "namespace": "JITRenderer", "metricName": "JobsQueued",
          "dimensions": {"Environment": "dev"},
          "statistic": "Sum", "period": "60", "region": "default"
        },
        {
          "refId": "B", "alias": "Jobs Completed", "queryMode": "Metrics",
          "namespace": "JITRenderer", "metricName": "JobsCompleted",
          "dimensions": {"Environment": "dev"},
          "statistic": "Sum", "period": "60", "region": "default"
        }
      ]
    },
    {
      "id": 6, "type": "timeseries",
      "title": "Spot Interruptions",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
      "targets": [{
        "refId": "A", "alias": "Interruptions", "queryMode": "Metrics",
        "namespace": "JITRenderer", "metricName": "SpotInterruptions",
        "dimensions": {"Environment": "dev"},
        "statistic": "Sum", "period": "300", "region": "default"
      }]
    }
  ]
}

with open('/var/lib/grafana/dashboards/jit-renderer.json', 'w') as f:
    json.dump(dashboard, f, indent=2)
print("Dashboard written.")
PYEOF

    chown -R grafana:grafana /var/lib/grafana

    # ── Start services ────────────────────────────────────────────────────────
    systemctl daemon-reload
    systemctl enable prometheus grafana-server
    systemctl start prometheus
    systemctl start grafana-server

    echo "[setup] complete at $(date -u)"
    echo "[setup] Grafana: http://$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4):3000"
    echo "[setup] Login: admin / admin (change on first login)"
  BASH
  )

  tags = { Name = "${var.project_name}-observability-${var.environment}" }
}
