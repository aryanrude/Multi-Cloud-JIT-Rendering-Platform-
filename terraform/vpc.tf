# Use default VPC — avoids managing subnets, IGW, route tables
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── EC2 render worker SG ──────────────────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-${var.environment}"
  description = "Render worker EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  # All outbound: callback API, SSM, ElastiCache, dnf packages
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ec2-${var.environment}" }
}

# ── ElastiCache SG ────────────────────────────────────────────────────────────
resource "aws_security_group" "elasticache" {
  name        = "${var.project_name}-cache-${var.environment}"
  description = "ElastiCache Redis - EC2 workers only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Redis from EC2 workers"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-cache-${var.environment}" }
}
