# IAM Module

Creates IAM roles for Kubernetes controllers using IRSA (IAM Roles for Service Accounts).

## Features

- AWS Load Balancer Controller IAM role
- ExternalDNS IAM role
- cert-manager IAM role
- Proper trust policies for OIDC authentication

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  project_name      = "expense-tracker"
  environment       = "prod"
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  
  enable_aws_lb_controller = true
  enable_external_dns      = true
  enable_cert_manager      = true
}
```

## Roles Created

### AWS Load Balancer Controller
- Creates and manages ALBs/NLBs for Kubernetes Services and Ingresses
- Permissions: EC2, ELB, ACM, WAF, Shield

### ExternalDNS
- Automatically manages Route 53 DNS records based on Kubernetes resources
- Permissions: Route 53 ChangeResourceRecordSets, ListHostedZones

### cert-manager
- Manages TLS certificates using Let's Encrypt with DNS01 challenge
- Permissions: Route 53 for DNS validation

## Outputs

| Name | Description |
|------|-------------|
| aws_lb_controller_role_arn | IAM Role ARN for LB Controller |
| external_dns_role_arn | IAM Role ARN for ExternalDNS |
| cert_manager_role_arn | IAM Role ARN for cert-manager |

## Service Account Annotations

To use these roles, annotate your Kubernetes service accounts:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/CLUSTER-aws-lb-controller-role
```
