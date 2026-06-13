output "grafana_url" {
  description = "Grafana dashboard URL — login: admin / admin"
  value       = "http://${aws_instance.observability.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL (internal access only)"
  value       = "http://${aws_instance.observability.private_ip}:9090"
}

output "observability_instance_id" {
  description = "Observability EC2 instance ID"
  value       = aws_instance.observability.id
}
