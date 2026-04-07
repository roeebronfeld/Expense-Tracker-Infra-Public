# Centralized Logging — CloudWatch + FluentBit
#
# Creates:
#   - CloudWatch Log Group with retention policy
#   - IAM policy attached to the node group role for CloudWatch access
#
# FluentBit runs as a DaemonSet (via ArgoCD aws-for-fluent-bit chart) and
# inherits CloudWatch permissions from the node IAM role — the standard
# AWS pattern for node-level logging agents.

# ─────────────────────────────────────────────────
# CloudWatch Log Group
# ─────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "eks_containers" {
  name              = "/eks/${local.cluster_name}/containers"
  retention_in_days = 30

  tags = {
    Component = "logging"
  }
}

# ─────────────────────────────────────────────────
# CloudWatch Logs policy → Node Group IAM Role
# ─────────────────────────────────────────────────

resource "aws_iam_policy" "fluent_bit" {
  name        = "${local.cluster_name}-fluent-bit-policy"
  description = "IAM policy for FluentBit to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.eks_containers.arn,
          "${aws_cloudwatch_log_group.eks_containers.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fluent_bit" {
  policy_arn = aws_iam_policy.fluent_bit.arn
  role       = module.eks.eks_managed_node_groups["general"].iam_role_name
}
