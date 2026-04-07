# IAM Module
# Creates IAM roles for Kubernetes controllers.
# Supports both IRSA (OIDC-based) and EKS Pod Identity.
#
#

locals {
  oidc_provider = replace(var.oidc_provider_url, "https://", "")

  common_tags = {
    Module      = "iam"
    Project     = var.project_name
    Environment = var.environment
  }

  # Pod Identity trust policy
  pod_identity_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

# AWS Load Balancer Controller IAM Role
resource "aws_iam_role" "aws_lb_controller" {
  count = var.enable_aws_lb_controller ? 1 : 0

  name = "${var.cluster_name}-aws-lb-controller-role"

  assume_role_policy = var.use_pod_identity ? local.pod_identity_trust_policy : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-aws-lb-controller-role"
  })
}

resource "aws_iam_policy" "aws_lb_controller" {
  count = var.enable_aws_lb_controller ? 1 : 0

  name        = "${var.cluster_name}-aws-lb-controller-policy"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = file("${path.module}/policies/aws-lb-controller-policy.json")

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  count = var.enable_aws_lb_controller ? 1 : 0

  policy_arn = aws_iam_policy.aws_lb_controller[0].arn
  role       = aws_iam_role.aws_lb_controller[0].name
}

# ExternalDNS IAM Role
resource "aws_iam_role" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name = "${var.cluster_name}-external-dns-role"

  assume_role_policy = var.use_pod_identity ? local.pod_identity_trust_policy : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:sub" = "system:serviceaccount:external-dns:external-dns"
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-external-dns-role"
  })
}

resource "aws_iam_policy" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name        = "${var.cluster_name}-external-dns-policy"
  description = "IAM policy for ExternalDNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  policy_arn = aws_iam_policy.external_dns[0].arn
  role       = aws_iam_role.external_dns[0].name
}

# cert-manager IAM Role (for DNS01 challenge with Route53)
resource "aws_iam_role" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name = "${var.cluster_name}-cert-manager-role"

  assume_role_policy = var.use_pod_identity ? local.pod_identity_trust_policy : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cert-manager-role"
  })
}

resource "aws_iam_policy" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name        = "${var.cluster_name}-cert-manager-policy"
  description = "IAM policy for cert-manager DNS01 challenge"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange"
        ]
        Resource = ["arn:aws:route53:::change/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZonesByName",
          "route53:ListHostedZones"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  policy_arn = aws_iam_policy.cert_manager[0].arn
  role       = aws_iam_role.cert_manager[0].name
}

# External Secrets Operator IAM Role
# Allows External Secrets Operator to read secrets from AWS Secrets Manager
# and sync them to Kubernetes Secrets
resource "aws_iam_role" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name = "${var.cluster_name}-external-secrets-role"

  assume_role_policy = var.use_pod_identity ? local.pod_identity_trust_policy : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-external-secrets-role"
  })
}

resource "aws_iam_policy" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name        = "${var.cluster_name}-external-secrets-policy"
  description = "IAM policy for External Secrets Operator to read from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        # If specific ARNs provided, use them; otherwise allow all secrets in account
        # TODO: For production, always specify exact secret ARNs
        Resource = length(var.secrets_manager_secret_arns) > 0 ? var.secrets_manager_secret_arns : ["arn:aws:secretsmanager:*:*:secret:${var.project_name}/*"]
      },
      {
        Sid    = "SecretsManagerList"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  policy_arn = aws_iam_policy.external_secrets[0].arn
  role       = aws_iam_role.external_secrets[0].name
}
