data "aws_iam_policy_document" "lambda_phase2" {
  # EC2 — launch spot instances via launch template
  statement {
    sid    = "EC2Launch"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"] # RunInstances requires * for subnets, AMIs, etc.
  }

  # IAM — pass the EC2 instance role when launching instances
  statement {
    sid       = "IAMPassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ec2_instance.arn]
  }

  # SQS — required for Lambda SQS event source mapping polling
  statement {
    sid    = "SQSConsume"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.render_jobs.arn]
  }
}

resource "aws_iam_policy" "lambda_phase2" {
  name   = "${var.project_name}-lambda-phase2-${var.environment}"
  policy = data.aws_iam_policy_document.lambda_phase2.json
}

resource "aws_iam_role_policy_attachment" "lambda_phase2" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_phase2.arn
}
