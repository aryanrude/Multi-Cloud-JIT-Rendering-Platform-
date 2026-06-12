data "archive_file" "provisioner" {
  type        = "zip"
  source_dir  = "${path.module}/../src/provisioner"
  output_path = "${path.module}/../dist/provisioner.zip"
}

resource "aws_cloudwatch_log_group" "provisioner" {
  name              = "/aws/lambda/${var.project_name}-provisioner-${var.environment}"
  retention_in_days = 14
}

resource "aws_lambda_function" "provisioner" {
  function_name    = "${var.project_name}-provisioner-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.provisioner.output_path
  source_code_hash = data.archive_file.provisioner.output_base64sha256
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      RENDER_JOBS_TABLE  = aws_dynamodb_table.render_jobs.name
      LAUNCH_TEMPLATE_ID = aws_launch_template.render_worker.id
      ENVIRONMENT        = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.provisioner,
  ]
}

# SQS triggers Provisioner Lambda automatically — no polling needed in code
resource "aws_lambda_event_source_mapping" "provisioner_sqs" {
  event_source_arn = aws_sqs_queue.render_jobs.arn
  function_name    = aws_lambda_function.provisioner.arn
  batch_size       = 1     # one job at a time — each job = one EC2 launch
  enabled          = true
}
