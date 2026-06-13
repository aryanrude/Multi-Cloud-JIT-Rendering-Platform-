resource "aws_iam_role" "observability" {
  name = "${var.project_name}-observability-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Read all CloudWatch metrics — Grafana needs this to query any namespace
resource "aws_iam_role_policy_attachment" "observability_cloudwatch" {
  role       = aws_iam_role.observability.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# SSM for console access during debugging
resource "aws_iam_role_policy_attachment" "observability_ssm" {
  role       = aws_iam_role.observability.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "observability" {
  name = "${var.project_name}-observability-${var.environment}"
  role = aws_iam_role.observability.name
}
