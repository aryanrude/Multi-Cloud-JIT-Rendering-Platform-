output "launch_template_id" {
  description = "EC2 launch template — used by provisioner Lambda to launch workers"
  value       = aws_launch_template.render_worker.id
}

output "elasticache_host" {
  description = "Redis endpoint — Bootstrap Agent caches config here"
  value       = aws_elasticache_cluster.config_cache.cache_nodes[0].address
}

output "provisioner_function" {
  description = "Provisioner Lambda name — triggered by SQS automatically"
  value       = aws_lambda_function.provisioner.function_name
}

output "spot_handler_function" {
  description = "Spot Handler Lambda name — triggered by EventBridge on interruption"
  value       = aws_lambda_function.spot_handler.function_name
}
