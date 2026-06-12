# Both parameters are read by the Bootstrap Agent running on EC2.
# Lambda never touches ElastiCache directly — only EC2 does.

resource "aws_ssm_parameter" "callback_url" {
  name  = "/${var.project_name}/${var.environment}/callback_url"
  type  = "String"
  value = "${aws_api_gateway_stage.main.invoke_url}/callback"
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "/${var.project_name}/${var.environment}/redis_host"
  type  = "String"
  value = aws_elasticache_cluster.config_cache.cache_nodes[0].address
}
