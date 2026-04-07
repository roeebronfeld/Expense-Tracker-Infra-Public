# GitHub Actions OIDC Module

This module creates the IAM resources needed for GitHub Actions to authenticate with AWS using OIDC (OpenID Connect) instead of static AWS credentials.

## Benefits

- **No static credentials**: No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` to manage
- **Automatic rotation**: OIDC tokens are short-lived and automatically rotated
- **Fine-grained access**: Restrict access to specific repositories, branches, and environments
- **Audit trail**: All assumptions logged in CloudTrail
- **Security**: Follows AWS and GitHub security best practices

## Usage

```hcl
module "github_oidc" {
  source = "../modules/github-oidc"

  project_name      = "expense-tracker"
  environment       = "dev"
  github_repository = "roeebronfeld/Expense-Tracker-App"
  github_branch     = "main"
  aws_account_id    = "123456789012"
  aws_region        = "us-east-1"
}
```

## GitHub Actions Workflow

After applying this module, update your GitHub Actions workflow:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/expense-tracker-dev-github-actions-role
    aws-region: us-east-1
```

## Required GitHub Repository Settings

1. Go to your repository Settings → Secrets and variables → Actions
2. **Remove** the following secrets (they are no longer needed):
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

## Security Hardening TODO

For production environments, the IAM policy should be scoped down:

1. **EKS**: Restrict to specific cluster ARN
2. **ECR**: Restrict to specific repository ARNs
3. **Secrets Manager**: Restrict to specific secret ARNs
4. **S3**: Only allow access to terraform state bucket

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| project_name | Name of the project | string | yes |
| environment | Environment name | string | yes |
| github_repository | GitHub repo (owner/repo) | string | yes |
| github_branch | Branch that can assume role | string | no (default: main) |
| aws_account_id | AWS Account ID | string | yes |
| aws_region | AWS region | string | no (default: us-east-1) |

## Outputs

| Name | Description |
|------|-------------|
| oidc_provider_arn | ARN of the GitHub OIDC provider |
| github_actions_role_arn | ARN of the IAM role for GitHub Actions |
| github_actions_config | Configuration for GitHub Actions workflow |
