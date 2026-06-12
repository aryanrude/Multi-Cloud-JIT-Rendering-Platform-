data "archive_file" "spot_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../src/spot_handler"
  output_path = "${path.module}/../dist/spot_handler.zip"
}

resource "aws_cloudwatch_log_group" "spot_handler" {
  name              = "/aws/lambda/${var.project_name}-spot-handler-${var.environment}"
  retention_in_days = 14
}

resource "aws_lambda_function" "spot_handler" {
  function_name    = "${var.project_name}-spot-handler-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.spot_handler.output_path
  source_code_hash = data.archive_file.spot_handler.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      RENDER_JOBS_TABLE = aws_dynamodb_table.render_jobs.name
      QUEUE_URL         = aws_sqs_queue.render_jobs.url
      ENVIRONMENT       = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.spot_handler,
  ]
}

# EventBridge fires ~2 min before AWS terminates the spot instance
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.project_name}-spot-interruption-${var.environment}"
  description = "EC2 Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_handler" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_lambda_function.spot_handler.arn
}

resource "aws_lambda_permission" "spot_handler_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.spot_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.spot_interruption.arn
}
