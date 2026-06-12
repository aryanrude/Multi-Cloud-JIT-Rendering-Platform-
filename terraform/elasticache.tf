resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-cache-subnets-${var.environment}"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_elasticache_cluster" "config_cache" {
  # Max 20 chars for cluster_id
  cluster_id = "jit-${var.environment}-cfg"

  engine               = "redis"
  node_type            = "cache.t3.micro" # ~$12/month — upgrade for prod
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]
}
