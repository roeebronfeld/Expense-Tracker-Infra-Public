# Ephemeral Stack Runbook

End-to-end deploy and destroy guide for the Expense Tracker ephemeral stack.

Goal:
- rebuild production from zero in about 30 minutes
- avoid live patching during bootstrap
- keep destroy as reliable as deploy

This stack is designed to be:
- fully recreated from Terraform
- GitOps-managed after bootstrap
- safe to destroy and rebuild

## Scope

Repositories involved:
- `Expense-Tracker-Infra-Public`
- `Expense-Tracker-gitops-Public`
- `Expense-Tracker-App-Public`

AWS region:
- `us-east-1`

Cluster name:
- `expense-tracker-prod-cluster`

Only `prod` is in scope.
`staging` is intentionally out of the active flow.

## Preflight

Do not start the deploy until every item below is true.

### Repositories and branches

- `App`, `Infra`, and `gitops` all point to their `Public` repos
- all three repos are on the branch you actually want to deploy
- `App` and `Infra` working trees are clean

Helpful checks:

```bash
git -C Expense-Tracker-App remote -v
git -C Expense-Tracker-Infra remote -v
git -C Expense-Tracker-gitops remote -v
git -C Expense-Tracker-App status --short
git -C Expense-Tracker-Infra status --short
```

### AWS and local tooling

- AWS CLI is authenticated to account `123456789012`
- Docker daemon is running
- Terraform is available
- `kubectl`, `helm`, `jq` are installed
- the Terraform state bucket already exists

Helpful checks:

```bash
aws sts get-caller-identity
docker info >/dev/null
terraform version
kubectl version --client
helm version
jq --version
```

### Terraform variables and secrets

Before `terraform apply`, verify:

- `terraform/environments/prod/terraform.tfvars` exists
- `github_repository = "roeebronfeld/Expense-Tracker-App-Public"`
- the GitHub App private key is current
- optional OAuth secrets are valid if enabled

Helpful check:

```bash
rg -n "^github_repository\\s*=" Expense-Tracker-Infra/terraform/environments/prod/terraform.tfvars
```

### CI/CD assumptions

Before relying on automation:

- App CI uses the private app repo
- CD updates the private GitOps repo
- AWS OIDC trust policy is aligned to `Expense-Tracker-App-Public`

Helpful check:

```bash
terraform -chdir=Expense-Tracker-Infra/terraform/environments/prod plan -target=module.github_oidc -no-color
```

Expected result:
- `No changes` or only the exact repo/branch trust-policy change you intend

### Do not start if

- Docker is not running
- the GitHub App key was rotated but `terraform.tfvars` still has the old key
- `github_repository` in `terraform.tfvars` still points to the public app repo
- you have not decided which image tag GitOps should run

## Deploy

### 1. Apply infrastructure

```bash
cd Expense-Tracker-Infra/terraform/environments/prod
terraform init -input=false
terraform apply -input=false
```

Expected result:
- VPC, EKS, ECR, IAM, ACM, Secrets Manager, ArgoCD
- root ArgoCD application created automatically

### 2. Refresh kubeconfig after cluster is ACTIVE

Important:
- run this again after the cluster finishes creating
- the EKS API endpoint can change during creation

```bash
aws eks update-kubeconfig --region us-east-1 --name expense-tracker-prod-cluster
kubectl get nodes
```

Expected result:
- two worker nodes in `Ready`

### 3. Push app images before waiting on workloads

Do not wait for app pods before images exist in ECR.

Production GitOps currently expects the image tags defined in:
- `Expense-Tracker-gitops/environments/prod/backend-values.yaml`
- `Expense-Tracker-gitops/environments/prod/frontend-values.yaml`

Check them first:

```bash
sed -n '1,40p' Expense-Tracker-gitops/environments/prod/backend-values.yaml
sed -n '1,40p' Expense-Tracker-gitops/environments/prod/frontend-values.yaml
```

Login once:

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
```

Backend:

```bash
cd Expense-Tracker-App
docker build -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/expense-tracker-backend:v1.0.0 app/backend
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/expense-tracker-backend:v1.0.0
```

Frontend:

```bash
cd Expense-Tracker-App
docker build -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/expense-tracker-frontend:v1.0.0 app/frontend
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/expense-tracker-frontend:v1.0.0
```

### 4. Validate platform convergence first

Check platform apps before checking app UX:

```bash
kubectl get applications -n argocd
kubectl get pods -A
kubectl get externalsecret -A
kubectl get secret grafana-admin-secret -n monitoring
```

Healthy target state:
- ArgoCD pods running
- `postgresql`, `external-secrets`, `external-dns`, `cert-manager`, `fluent-bit` healthy
- app pods in `expense-tracker` running
- Grafana running in `monitoring`
- `grafana-admin-secret` present

### 5. Validate ingress and DNS

```bash
kubectl get ingress -A
nslookup app.prod.roctl23.online
nslookup graf.prod.roctl23.online
nslookup argocd.prod.roctl23.online
```

Expected result:
- `app.prod.roctl23.online` resolves to the public ALB
- `graf.prod.roctl23.online` and `argocd.prod.roctl23.online` resolve to the ops ALB

### 6. Validate ArgoCD state

```bash
kubectl get applications.argoproj.io -n argocd
```

Healthy target state:
- every application is `Healthy`
- every application is `Synced`

If the cluster is healthy but ArgoCD is `OutOfSync`, stop and fix Git, do not patch live unless absolutely necessary.

### 7. Validate live production

```bash
curl -I https://app.prod.roctl23.online
curl -I https://graf.prod.roctl23.online
curl -I https://argocd.prod.roctl23.online
```

Expected result:
- app returns `200`
- Grafana returns `302` to `/login`
- ArgoCD returns `200`

Optional smoke test:
- register a user
- create / update / delete a category
- create / update / delete an expense
- create / update / delete a budget

## Common Issues

### EKS API endpoint does not resolve right after apply

Symptom:
- `kubectl` fails with DNS/NXDOMAIN against the cluster endpoint

Fix:

```bash
aws eks describe-cluster --region us-east-1 --name expense-tracker-prod-cluster --query 'cluster.[status,endpoint]' --output text
aws eks update-kubeconfig --region us-east-1 --name expense-tracker-prod-cluster
```

### Workloads stuck in `ErrImagePull`

Cause:
- ECR repositories exist, but the expected tags were never pushed

Fix:
- build and push the exact tags referenced by GitOps before waiting on app pods

### ArgoCD or GitOps apps show `401 Unauthorized`

Cause:
- GitHub App private key in `terraform.tfvars` is stale

Fix:
- update the private key in `Expense-Tracker-Infra/terraform/environments/prod/terraform.tfvars`
- re-run `terraform apply`

### Docker build/push in GitHub Actions fails on `AssumeRoleWithWebIdentity`

Cause:
- AWS OIDC trust policy points at the wrong GitHub repo

Fix:
- ensure `github_repository = "roeebronfeld/Expense-Tracker-App-Public"` in Terraform
- re-apply `module.github_oidc`

### Grafana stuck in `CreateContainerConfigError`

Cause:
- `grafana-admin-secret` not present yet

Fix:

```bash
kubectl get externalsecret -n monitoring
kubectl get secret grafana-admin-secret -n monitoring
```

If missing, refresh `external-secrets` first. Only patch live if the secret still does not appear after reconciliation.

### App is healthy but edit/delete looks broken in the UI

Cause:
- old frontend bundle in browser cache

Fix:
- hard refresh with `Ctrl+Shift+R`
- or test in incognito

## Operating Rules

To keep future deploys smooth:

- do not paste credentials into chat or terminal history unnecessarily
- do not patch Kubernetes live before Git and CI/CD are aligned
- do not treat `Healthy + OutOfSync` as success
- do not reintroduce `staging` into the critical deploy path unless it is maintained properly

## Destroy

Use the dedicated destroy sequence:

1. Gracefully remove GitOps-managed ingress and workloads
2. Wait for ALBs / ENIs to drain
3. Run Terraform destroy

Full procedure:
- see [DESTROY_RUNBOOK.md](/home/roeebron/projects/repo-split-workspace/Expense-Tracker-Infra/DESTROY_RUNBOOK.md)

Core destroy command:

```bash
cd Expense-Tracker-Infra/terraform/environments/prod
terraform destroy -input=false
```

## Post-Destroy Verification

```bash
aws eks list-clusters --region us-east-1 --query "clusters"
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?contains(LoadBalancerName, 'expense')]"
aws ec2 describe-vpcs --region us-east-1 --filters "Name=tag:Name,Values=expense-tracker-prod-vpc" --query "Vpcs[*].VpcId"
aws ecr describe-repositories --region us-east-1 --query "repositories[?contains(repositoryName, 'expense-tracker')]"
aws secretsmanager list-secrets --region us-east-1 --filters Key=name,Values=expense-tracker --query "SecretList[*].Name"
```

Expected result:
- cluster gone
- ALBs gone
- VPC gone
- ECR repos gone after destroy
- ephemeral secrets gone
- S3 state bucket still exists

Note:
- ALB names are often truncated by AWS, so search for `expense`, not only `expense-tracker`
