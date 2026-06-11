output "provision_endpoint" {
  description = "POST to this URL to submit a provisioning request"
  value       = "${aws_api_gateway_stage.main.invoke_url}/provision"
}

output "callback_endpoint" {
  description = "POST to this URL when a VM is ready (called by Bootstrap Agent)"
  value       = "${aws_api_gateway_stage.main.invoke_url}/callback"
}

output "compatibility_matrix_table" {
  description = "Seed this table with valid software/engine combinations"
  value       = aws_dynamodb_table.compatibility_matrix.name
}

output "render_jobs_table" {
  description = "Job tracking table — query status-index to see all jobs by status"
  value       = aws_dynamodb_table.render_jobs.name
}

output "render_jobs_queue_url" {
  description = "SQS queue URL — messages land here after orchestrator validates"
  value       = aws_sqs_queue.render_jobs.url
}

output "dlq_url" {
  description = "Dead letter queue — check here if jobs disappear"
  value       = aws_sqs_queue.render_jobs_dlq.url
}
