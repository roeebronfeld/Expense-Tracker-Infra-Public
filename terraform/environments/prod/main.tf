# Expense Tracker - Production Environment
# Main entry point for the production environment.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # S3 Backend for state management with locking
  backend "s3" {
    bucket       = "roeebron-expense-tracker-tf-state"
    key          = "expense-tracker/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # S3 native locking (no DynamoDB needed)
  }
}

# Providers
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Team        = "platform"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Local Variables
locals {
  cluster_name = "${var.project_name}-${var.environment}-cluster"
  azs          = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# GitHub Actions OIDC Module (Custom)
# Enables GitHub Actions to authenticate via OIDC instead of static credentials
module "github_oidc" {
  source = "../../modules/github-oidc"

  project_name      = var.project_name
  environment       = var.environment
  github_repository = var.github_repository
  github_branch     = var.github_branch
  aws_account_id    = data.aws_caller_identity.current.account_id
  aws_region        = var.aws_region
}

# ECR Module - Container Registry (Custom)
# ECR repositories for container images with lifecycle policies
module "ecr" {
  source = "../../modules/ecr"

  project_name         = var.project_name
  environment          = var.environment
  image_tag_mutability = "MUTABLE" # Allow tag updates for dev
  scan_on_push         = true      # Security scanning on every push
  keep_image_count     = 30        # Keep last 30 tagged images
  untagged_image_days  = 14        # Delete untagged after 14 days
  force_delete         = true      # Allow terraform destroy to delete repos with images
}

# VPC Module (terraform-aws-modules/vpc/aws)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + length(local.azs))]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]

  # NAT Gateway configuration
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # DNS settings (required for EKS)
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required for internet-facing ALB
  map_public_ip_on_launch = true

  # Tags for EKS subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# EKS Module (terraform-aws-modules/eks/aws)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_cluster_version

  # Networking
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Cluster endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable OIDC provider for IRSA
  enable_irsa = true

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    # Metrics Server - Required for HPA and kubectl top
    metrics-server = {
      most_recent = true
    }
  }

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    general = {
      name           = "general" # Keep short to avoid IAM role name limit
      instance_types = var.eks_node_groups.general.instance_types
      capacity_type  = var.eks_node_groups.general.capacity_type

      min_size     = var.eks_node_groups.general.min_size
      max_size     = var.eks_node_groups.general.max_size
      desired_size = var.eks_node_groups.general.desired_size

      disk_size = var.eks_node_groups.general.disk_size

      # AL2023 natively supports VPC CNI prefix delegation for higher pod density
      ami_type = "AL2023_x86_64_STANDARD"

      # Kubelet must be told about the increased pod limit from prefix delegation.
      # Without this, max-pods stays at 17 (ENI-based) despite prefix delegation being enabled.
      cloudinit_pre_nodeadm = [{
        content_type = "application/node.eks.aws"
        content      = <<-EOT
          ---
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              config:
                maxPods: 110
        EOT
      }]

      labels = var.eks_node_groups.general.labels
    }
  }

  # Cluster access - allow admin from current caller
  enable_cluster_creator_admin_permissions = true

  # Allow control plane to reach metrics-server on port 10251
  node_security_group_additional_rules = {
    ingress_metrics_server = {
      description                   = "Cluster API to metrics-server"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # GitHub Actions role needs cluster access for CD pipeline (ArgoCD sync, kubectl)
  access_entries = {
    github_actions = {
      principal_arn = module.github_oidc.github_actions_role_arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# EBS CSI Driver IRSA (required for EBS volumes in EKS 1.23+)
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# Mark gp2 StorageClass as default (EKS creates gp2 but doesn't set it as default)
resource "kubernetes_annotations" "gp2_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "true"
  }

  depends_on = [module.eks]
}

# IAM Module - Roles for Kubernetes controllers (Custom)
module "iam" {
  source = "../../modules/iam"

  project_name      = var.project_name
  environment       = var.environment
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.cluster_oidc_issuer_url

  # Use EKS Pod Identity (eliminates IRSA annotations in GitOps)
  use_pod_identity = true

  # Enable IAM roles for specific controllers
  enable_aws_lb_controller = true
  enable_external_dns      = true
  enable_cert_manager      = true # Required for automatic TLS via Let's Encrypt
  enable_external_secrets  = true

  # Allow ESO to access all secrets in our prefixes
  secrets_manager_secret_arns = [
    "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:argocd/*",
    "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:expense-tracker/*"
  ]
}

# ACM Certificate Module - Wildcard certificate for apex domain (Custom)
# Creates *.roctl23.online - covers app.roctl23.online, api.roctl23.online, etc.
module "acm" {
  source = "../../modules/acm"

  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name] # Include apex domain
  hosted_zone_name          = var.domain_name
  project_name              = var.project_name
  environment               = var.environment
}

# ACM Certificate for Environment Subdomain (Custom)
# Creates *.prod.roctl23.online for environment subdomains
# Wildcard certs only cover one level of subdomains
module "acm_env" {
  source = "../../modules/acm"

  domain_name               = "*.${var.environment}.${var.domain_name}"
  subject_alternative_names = ["${var.environment}.${var.domain_name}"] # Include dev.roctl23.online
  hosted_zone_name          = var.domain_name
  project_name              = var.project_name
  environment               = "${var.environment}-subdomain"
}
