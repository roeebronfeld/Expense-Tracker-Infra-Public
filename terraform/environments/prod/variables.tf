# Production Environment Variables

# General Configuration
variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "expense-tracker"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway instead of one per AZ (cost saving for dev)"
  type        = bool
  default     = true
}

# EKS Configuration
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_node_groups" {
  description = "Configuration for EKS managed node groups"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = {
    general = {
      instance_types = ["t3.medium", "t3a.medium"]
      capacity_type  = "ON_DEMAND" # Changed from SPOT due to capacity issues
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 30
      labels = {
        "node-type" = "general"
      }
      taints = []
    }
  }
}

variable "domain_name" {
  description = "Domain name for ExternalDNS (Route53 hosted zone)"
  type        = string
  default     = "roctl23.online"
}

# GitHub Actions OIDC Configuration
variable "github_repository" {
  description = "GitHub repository in format owner/repo (App repo with CI/CD workflows)"
  type        = string
  default     = "roeebronfeld/Expense-Tracker-App-Public"
}

variable "github_branch" {
  description = "GitHub branch that can assume the IAM role"
  type        = string
  default     = "main"
}

# ArgoCD Configuration
variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.3.11"
}

variable "github_org" {
  description = "GitHub organization or username for ArgoCD repo credentials"
  type        = string
  default     = "roeebronfeld"
}

variable "github_app_id" {
  description = "GitHub App ID for ArgoCD repository access"
  type        = string
  default     = "YOUR_GITHUB_APP_ID"
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID for ArgoCD repository access"
  type        = string
  default     = "YOUR_GITHUB_APP_INSTALLATION_ID"
}

# ─── Ephemeral Secrets (passed via tfvars, recreated on every apply) ───

variable "github_app_private_key" {
  description = "GitHub App private key PEM for ArgoCD repository access"
  type        = string
  sensitive   = true
}

variable "grafana_oauth_client_id" {
  description = "Google OAuth client ID for Grafana SSO (empty = SSO disabled)"
  type        = string
  default     = ""
}

variable "grafana_oauth_client_secret" {
  description = "Google OAuth client secret for Grafana SSO"
  type        = string
  sensitive   = true
  default     = ""
}

variable "argocd_oauth_client_id" {
  description = "Google OAuth client ID for ArgoCD SSO (empty = SSO disabled)"
  type        = string
  default     = ""
}

variable "argocd_oauth_client_secret" {
  description = "Google OAuth client secret for ArgoCD SSO"
  type        = string
  sensitive   = true
  default     = ""
}
