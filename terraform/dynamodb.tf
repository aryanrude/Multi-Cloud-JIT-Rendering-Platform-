resource "aws_dynamodb_table" "compatibility_matrix" {
  name         = "${var.project_name}-compatibility-matrix-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "combo_id"

  attribute {
    name = "combo_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# Tracks every job from queued → provisioning → ready → failed
resource "aws_dynamodb_table" "render_jobs" {
  name         = "${var.project_name}-render-jobs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # Query all jobs by status — useful for dashboards and debugging
  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"
  }

  # Auto-expire old job records after 24 hours
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }
}
