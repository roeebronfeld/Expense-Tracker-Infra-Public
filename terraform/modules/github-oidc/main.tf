# GitHub Actions OIDC Module
# Creates IAM resources for GitHub Actions to authenticate via OIDC
# instead of using static AWS credentials.
#

locals {
  github_oidc_provider_url = "https://token.actions.githubusercontent.com"
  # GitHub's current certificate thumbprint (as of 2024)
  # Note: AWS no longer validates thumbprints for well-known OIDC providers like GitHub,
  # but we still need to provide one for the terraform resource
  github_oidc_thumbprint = "1b511abead59c6ce207077c0bf0e0043b1382612"

  common_tags = {
    Module      = "github-oidc"
    Project     = var.project_name
    Environment = var.environment
  }
}

# GitHub OIDC Identity Provider
# This allows GitHub Actions to assume IAM roles using OIDC tokens
# instead of static AWS credentials
resource "aws_iam_openid_connect_provider" "github" {
  url             = local.github_oidc_provider_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [local.github_oidc_thumbprint]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-github-oidc-provider"
    Description = "GitHub Actions OIDC provider for secure AWS authentication"
  })
}

# IAM Role for GitHub Actions
# This role can be assumed by GitHub Actions workflows from the specified
# repository and branch only
resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-${var.environment}-github-actions-role"
  description = "IAM role for GitHub Actions CD pipeline"

  # Trust policy - Only allow the specific repository and branch to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Restrict to main branch, version tags, and environment deployments
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}",
              "repo:${var.github_repository}:ref:refs/tags/v*",
              "repo:${var.github_repository}:environment:${var.environment}"
            ]
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-github-actions-role"
  })
}

# IAM Policy for GitHub Actions
# NOTE: This is a broad policy for learning/dev environment.
# TODO: For production, scope down to specific resources:
# - EKS: Only the specific cluster ARN
# - ECR: Only the specific repository ARNs  
# - Secrets Manager: Only specific secret ARNs
# - S3: Only terraform state bucket
resource "aws_iam_policy" "github_actions" {
  name        = "${var.project_name}-${var.environment}-github-actions-policy"
  description = "Policy for GitHub Actions CD pipeline - TODO: Scope down for production"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EKS Access - Required for kubectl commands and ArgoCD sync
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
        # TODO: Scope to specific cluster ARN:
        # Resource = "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.cluster_name}"
      },
      # ECR Access - Required for pulling/pushing container images
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      # Secrets Manager - Required for reading DB credentials
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
        # TODO: Scope to specific secrets:
        # Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/*"
      },
      # S3 Access - Required for Terraform state (if running Terraform in CI)
      {
        Sid    = "S3TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*-terraform-state",
          "arn:aws:s3:::${var.project_name}-*-terraform-state/*"
        ]
      },
      # STS - Required for getting caller identity (debugging)
      {
        Sid    = "STSGetCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "github_actions" {
  policy_arn = aws_iam_policy.github_actions.arn
  role       = aws_iam_role.github_actions.name
}

# NOTE: EKS access is granted via EKS access_entries (AmazonEKSClusterAdminPolicy)
# in the main EKS module, not through IAM managed policies.
# The custom policy above provides eks:DescribeCluster for kubeconfig generation.
