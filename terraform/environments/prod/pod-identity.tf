# EKS Pod Identity Associations


#

# AWS Load Balancer Controller - Pod Identity Association
resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = module.iam.aws_lb_controller_role_arn

  depends_on = [module.eks]
}

# External Secrets Operator - Pod Identity Association
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = module.iam.external_secrets_role_arn

  depends_on = [module.eks]
}

# ExternalDNS - Pod Identity Association
resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = module.iam.external_dns_role_arn

  depends_on = [module.eks]
}

# cert-manager - Pod Identity Association
resource "aws_eks_pod_identity_association" "cert_manager" {
  cluster_name    = module.eks.cluster_name
  namespace       = "cert-manager"
  service_account = "cert-manager"
  role_arn        = module.iam.cert_manager_role_arn

  depends_on = [module.eks]
}
