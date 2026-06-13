resource "aws_iam_role" "ec2_instance" {
  name = "${var.project_name}-ec2-instance-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

data "aws_iam_policy_document" "ec2_instance" {
  # Read-only access to the two SSM params the Bootstrap Agent needs
  statement {
    sid     = "SSMReadConfig"
    effect  = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.callback_url.arn,
      aws_ssm_parameter.redis_host.arn,
    ]
  }
}

resource "aws_iam_policy" "ec2_instance" {
  name   = "${var.project_name}-ec2-instance-${var.environment}"
  policy = data.aws_iam_policy_document.ec2_instance.json
}

resource "aws_iam_role_policy_attachment" "ec2_instance" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = aws_iam_policy.ec2_instance.arn
}
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_instance.name
}
