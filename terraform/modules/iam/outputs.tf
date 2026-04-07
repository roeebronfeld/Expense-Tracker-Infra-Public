# IAM Module Outputs

output "aws_lb_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = var.enable_aws_lb_controller ? aws_iam_role.aws_lb_controller[0].arn : ""
}

output "external_dns_role_arn" {
  description = "IAM Role ARN for ExternalDNS"
  value       = var.enable_external_dns ? aws_iam_role.external_dns[0].arn : ""
}

output "cert_manager_role_arn" {
  description = "IAM Role ARN for cert-manager"
  value       = var.enable_cert_manager ? aws_iam_role.cert_manager[0].arn : ""
}

output "external_secrets_role_arn" {
  description = "IAM Role ARN for External Secrets Operator"
  value       = var.enable_external_secrets ? aws_iam_role.external_secrets[0].arn : ""
}
