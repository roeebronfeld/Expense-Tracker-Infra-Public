# GitHub OIDC Module - Outputs

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_provider_url" {
  description = "URL of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.url
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.name
}

# Output the configuration needed for GitHub Actions workflow
output "github_actions_config" {
  description = "Configuration to use in GitHub Actions workflow"
  value = {
    role_to_assume = aws_iam_role.github_actions.arn
    aws_region     = var.aws_region
    # Instructions for workflow
    workflow_example = <<-EOT
      # Add this to your GitHub Actions workflow:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${aws_iam_role.github_actions.arn}
          aws-region: ${var.aws_region}
    EOT
  }
}
