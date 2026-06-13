data "aws_iam_policy_document" "lambda_metrics" {
  statement {
    sid       = "CloudWatchPutMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_metrics" {
  name   = "${var.project_name}-lambda-metrics-${var.environment}"
  policy = data.aws_iam_policy_document.lambda_metrics.json
}

resource "aws_iam_role_policy_attachment" "lambda_metrics" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_metrics.arn
}
