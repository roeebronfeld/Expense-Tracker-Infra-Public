# Expense Tracker - Infrastructure

Terraform infrastructure for the Expense Tracker application on AWS EKS.

## Architecture: Single Ephemeral Stack

Everything lives in one Terraform stack (`terraform/environments/prod/`). Run `terraform destroy` → `terraform apply` to rebuild from scratch with zero manual steps. Only two things persist outside the stack:

- **S3 state bucket** (`roeebron-expense-tracker-tf-state`) — created once via `terraform/bootstrap/`
- **Route53 hosted zone** (`roctl23.online`) — managed outside Terraform

### What the stack creates

- VPC (2 AZs, public + private subnets, single NAT gateway)
- EKS cluster (v1.31, 2× t3.medium, AL2023 AMI, prefix delegation: 110 pods/node)
- ECR repositories (backend + frontend)
- ACM certificates (wildcard for `*.roctl23.online` and `*.prod.roctl23.online`)
- IAM roles (Pod Identity for LB controller, external-dns, cert-manager, ESO, fluent-bit)
- Secrets Manager secrets (`recovery_window_in_days = 0` — immediate delete on destroy)
- CloudWatch log group (`/eks/expense-tracker-prod/containers`, 30-day retention)
- ArgoCD (Helm chart v7.3.11, GitHub App auth, app-of-apps bootstrap)
- StorageClass `gp2` marked as default

External credentials (GitHub App key, OAuth) are passed via `terraform.tfvars`.
Internal credentials (Grafana admin password) are auto-generated.

ArgoCD bootstraps all applications from the [GitOps repo](https://github.com/roeebronfeld/Expense-Tracker-gitops).

## Prerequisites

- AWS CLI configured (account `123456789012`, region `us-east-1`)
- Terraform >= 1.5.0
- kubectl
- S3 bucket `roeebron-expense-tracker-tf-state` (created via `terraform/bootstrap/`)

## Quick Start

```bash
# 1. First-time only: create S3 state bucket
cd terraform/bootstrap
terraform init && terraform apply

# 2. Deploy infrastructure
cd ../environments/prod
cp terraform.tfvars.example terraform.tfvars   # Edit with your values
terraform init
terraform apply   # ~15 min

# 3. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name expense-tracker-prod-cluster

# ArgoCD auto-syncs all apps. Wait ~5 min for full convergence.
```

### Destroy and recreate (zero manual steps)

```bash
cd terraform/environments/prod
terraform destroy   # ~10 min
terraform apply     # ~15 min
aws eks update-kubeconfig --region us-east-1 --name expense-tracker-prod-cluster
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Single ephemeral stack | Ensures `destroy` → `apply` works with zero manual steps |
| `recovery_window = 0` | Secrets deleted immediately — no 7/30-day wait on destroy |
| AL2023 AMI | Native prefix delegation support (110 pods/node vs 17) |
| Pod Identity | Eliminates IRSA annotations in GitOps — IAM managed entirely in Terraform |
| `gp2` default SC | Ensures PVCs bind without explicit storageClassName |
| GitHub App auth | ArgoCD authenticates to private GitOps repo via GitHub App (no PATs) |
| Single NAT gateway | Cost optimization for non-HA learning project |
| CloudWatch + FluentBit | Centralized logging with 30-day retention, no self-hosted log stack |

## Terraform State

| Stack | S3 Key |
|-------|--------|
| Bootstrap | Local (one-time) |
| Prod | `expense-tracker/prod/terraform.tfstate` |

## Directory Structure

```
terraform/
├── bootstrap/           # One-time S3 backend setup
│   └── main.tf
├── environments/
│   └── prod/            # Single ephemeral stack (destroy/apply freely)
│       ├── main.tf      # VPC, EKS, ECR, IAM, ACM, StorageClass
│       ├── argocd.tf    # ArgoCD Helm release + repo credentials + app-of-apps
│       ├── secrets.tf   # Secrets Manager (GitHub App, OIDC, Grafana admin)
│       ├── logging.tf   # CloudWatch log group + FluentBit IAM
│       ├── pod-identity.tf  # EKS Pod Identity associations
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── modules/             # Reusable modules
    ├── acm/             # ACM certificate with DNS validation
    ├── ecr/             # ECR repositories with lifecycle policies
    ├── github-oidc/     # GitHub Actions OIDC authentication
    └── iam/             # IAM roles for K8s controllers (Pod Identity)
```
