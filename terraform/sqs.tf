resource "aws_sqs_queue" "render_jobs_dlq" {
  name                      = "${var.project_name}-jobs-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days — long enough to investigate failures
}

resource "aws_sqs_queue" "render_jobs" {
  name = "${var.project_name}-jobs-${var.environment}"

  # Must be >= Lambda timeout to prevent duplicate processing
  visibility_timeout_seconds = 300

  message_retention_seconds = 86400 # 1 day

  # After 3 failed receive attempts, route to DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.render_jobs_dlq.arn
    maxReceiveCount     = 3
  })
}
