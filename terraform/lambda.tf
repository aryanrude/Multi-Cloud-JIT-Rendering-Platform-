data "archive_file" "orchestrator" {
  type        = "zip"
  source_dir  = "${path.module}/../src/orchestrator"
  output_path = "${path.module}/../dist/orchestrator.zip"
}

data "archive_file" "callback" {
  type        = "zip"
  source_dir  = "${path.module}/../src/callback"
  output_path = "${path.module}/../dist/callback.zip"
}

# ── Orchestrator ─────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${var.project_name}-orchestrator-${var.environment}"
  retention_in_days = 14
}

resource "aws_lambda_function" "orchestrator" {
  function_name    = "${var.project_name}-orchestrator-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.orchestrator.output_path
  source_code_hash = data.archive_file.orchestrator.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.compatibility_matrix.name
      RENDER_JOBS_TABLE = aws_dynamodb_table.render_jobs.name
      QUEUE_URL         = aws_sqs_queue.render_jobs.url
      ENVIRONMENT       = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.orchestrator,
  ]
}

# ── Callback ──────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "callback" {
  name              = "/aws/lambda/${var.project_name}-callback-${var.environment}"
  retention_in_days = 14
}

resource "aws_lambda_function" "callback" {
  function_name    = "${var.project_name}-callback-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.callback.output_path
  source_code_hash = data.archive_file.callback.output_base64sha256
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      RENDER_JOBS_TABLE = aws_dynamodb_table.render_jobs.name
      ENVIRONMENT       = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.callback,
  ]
}
