# IAM Module Variables

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC Provider ARN"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC Provider URL"
  type        = string
}

variable "enable_aws_lb_controller" {
  description = "Create IAM role for AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Create IAM role for ExternalDNS"
  type        = bool
  default     = false
}

variable "enable_cert_manager" {
  description = "Create IAM role for cert-manager"
  type        = bool
  default     = false
}

variable "enable_external_secrets" {
  description = "Create IAM role for External Secrets Operator"
  type        = bool
  default     = false
}

variable "use_pod_identity" {
  description = "Use EKS Pod Identity instead of IRSA. Pod Identity eliminates the need for ServiceAccount annotations."
  type        = bool
  default     = false
}

variable "secrets_manager_secret_arns" {
  description = "List of Secrets Manager secret ARNs that External Secrets can access"
  type        = list(string)
  default     = []
}
