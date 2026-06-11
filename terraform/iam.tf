data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# CloudWatch Logs — required for Lambda to write logs
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_permissions" {
  # Compatibility matrix — read only, never write from Lambda
  statement {
    sid       = "CompatibilityRead"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.compatibility_matrix.arn]
  }

  # Render jobs — orchestrator writes, callback updates
  statement {
    sid    = "RenderJobsReadWrite"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.render_jobs.arn,
      "${aws_dynamodb_table.render_jobs.arn}/index/*",
    ]
  }

  # SQS — orchestrator sends, nothing else
  statement {
    sid     = "SQSSend"
    effect  = "Allow"
    actions = ["sqs:SendMessage", "sqs:GetQueueUrl"]
    resources = [aws_sqs_queue.render_jobs.arn]
  }
}

resource "aws_iam_policy" "lambda_permissions" {
  name   = "${var.project_name}-lambda-policy-${var.environment}"
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_permissions" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}
