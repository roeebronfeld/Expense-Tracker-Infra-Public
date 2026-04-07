# Production Environment Outputs



# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

# EKS Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

# Kubeconfig Command
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# IAM Role ARNs (for ArgoCD Helm values)
output "aws_lb_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = module.iam.aws_lb_controller_role_arn
}

output "external_dns_role_arn" {
  description = "IAM Role ARN for ExternalDNS"
  value       = module.iam.external_dns_role_arn
}

output "external_secrets_role_arn" {
  description = "IAM Role ARN for External Secrets Operator"
  value       = module.iam.external_secrets_role_arn
}

# GitHub Actions OIDC Outputs
output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions (use this in your workflow)"
  value       = module.github_oidc.github_actions_role_arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN"
  value       = module.github_oidc.oidc_provider_arn
}

# ECR Outputs
output "ecr_backend_repository_url" {
  description = "URL of the backend ECR repository"
  value       = module.ecr.backend_repository_url
}

output "ecr_frontend_repository_url" {
  description = "URL of the frontend ECR repository"
  value       = module.ecr.frontend_repository_url
}

output "ecr_registry_url" {
  description = "ECR registry URL"
  value       = module.ecr.ecr_registry_url
}

# ArgoCD (installed declaratively via Terraform Helm provider)
output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = helm_release.argocd.namespace
}

# ACM Certificate Outputs
output "acm_certificate_arn" {
  description = "ARN of the wildcard ACM certificate (*.roctl23.online)"
  value       = module.acm.certificate_arn
}

output "acm_certificate_domain" {
  description = "Primary domain of the ACM certificate"
  value       = module.acm.certificate_domain
}

output "acm_env_certificate_arn" {
  description = "ARN of the environment subdomain ACM certificate (*.dev.roctl23.online)"
  value       = module.acm_env.certificate_arn
}

output "acm_env_certificate_domain" {
  description = "Primary domain of the environment subdomain ACM certificate"
  value       = module.acm_env.certificate_domain
}

output "route53_hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = module.acm.hosted_zone_id
}

# Secrets Outputs
output "argocd_oidc_secret_arn" {
  description = "ARN of the ArgoCD OIDC secret in Secrets Manager"
  value       = aws_secretsmanager_secret.argocd_oidc.arn
}

output "grafana_oidc_secret_arn" {
  description = "ARN of the Grafana OIDC secret in Secrets Manager"
  value       = aws_secretsmanager_secret.grafana_oidc.arn
}

output "grafana_admin_password" {
  description = "Auto-generated Grafana admin password"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "internal_services_domain" {
  description = "Base domain for internal services (argocd.prod.{domain}, grafana.prod.{domain})"
  value       = "${var.environment}.${var.domain_name}"
}

# CloudWatch Logging Outputs
output "cloudwatch_log_group_name" {
  description = "CloudWatch log group for EKS container logs"
  value       = aws_cloudwatch_log_group.eks_containers.name
}
