# Destroy Runbook — Expense Tracker

Stable 2-step destroy process to cleanly tear down the entire stack without orphaned AWS resources (ENIs, ALBs, target groups, security groups).

---

## Prerequisites

```bash
aws sts get-caller-identity          # Confirm correct account
aws eks update-kubeconfig --region us-east-1 --name expense-tracker-prod-cluster
kubectl get nodes                    # Confirm cluster access
```

---

## Step 1 — Kubernetes Graceful Cleanup

Remove all ALB-managed Ingresses and LoadBalancer services **before** destroying the VPC/EKS. This ensures the AWS Load Balancer Controller can de-provision ALBs, target groups, and ENIs cleanly.

> **CRITICAL**: You must disable ArgoCD auto-sync and remove finalizers **before** deleting Ingresses, otherwise ArgoCD will immediately re-create them and the ALBs will never drain.

```bash
# 1a. Disable ArgoCD auto-sync and remove finalizers on ALL applications
for app in $(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}'); do
  kubectl patch application "$app" -n argocd --type merge \
    -p '{"metadata":{"finalizers":null},"spec":{"syncPolicy":{"automated":null}}}' 2>/dev/null
  kubectl delete application "$app" -n argocd --wait=false 2>/dev/null
done

# 1b. Delete all Ingresses (triggers ALB controller to remove ALBs + target groups)
kubectl delete ingress --all -A

# 1c. Wait for ALBs to be fully deregistered (up to 4 min)
echo "Waiting for ALBs to drain..."
for i in $(seq 1 24); do
  ALB_COUNT=$(aws elbv2 describe-load-balancers --region us-east-1 \
    --query "LoadBalancers[?contains(LoadBalancerName, 'expense')] | length(@)" \
    --output text 2>/dev/null || echo "0")
  if [ "$ALB_COUNT" = "0" ]; then
    echo "All ALBs removed."
    break
  fi
  echo "  Still $ALB_COUNT ALB(s) remaining... ($i/24)"
  sleep 10
done

# 1d. Delete all workload namespaces (PVCs, pods, services)
kubectl delete namespace expense-tracker --wait=true --timeout=120s 2>/dev/null || true
kubectl delete namespace monitoring --wait=true --timeout=120s 2>/dev/null || true
kubectl delete namespace logging --wait=true --timeout=120s 2>/dev/null || true
kubectl delete namespace cert-manager --wait=true --timeout=120s 2>/dev/null || true
kubectl delete namespace external-dns --wait=true --timeout=120s 2>/dev/null || true
kubectl delete namespace external-secrets --wait=true --timeout=120s 2>/dev/null || true

# 1e. Delete ArgoCD namespace
kubectl delete namespace argocd --wait=true --timeout=120s 2>/dev/null || true

# 1f. Wait for ENIs to detach (up to 2 min)
VPC_ID=$(aws ec2 describe-vpcs --region us-east-1 \
  --filters "Name=tag:Name,Values=expense-tracker-prod-vpc" \
  --query "Vpcs[0].VpcId" --output text 2>/dev/null)

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  echo "Waiting for ENIs in VPC $VPC_ID to detach..."
  for i in $(seq 1 12); do
    ENI_COUNT=$(aws ec2 describe-network-interfaces --region us-east-1 \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=in-use" \
      --query "NetworkInterfaces[?Attachment.InstanceId==null] | length(@)" \
      --output text 2>/dev/null || echo "0")
    if [ "$ENI_COUNT" = "0" ]; then
      echo "All non-instance ENIs detached."
      break
    fi
    echo "  Still $ENI_COUNT orphan ENI(s)... ($i/12)"
    sleep 10
  done
fi
```

---

## Step 2 — Terraform Destroy

```bash
cd Expense-Tracker-Infra/terraform/environments/prod
terraform destroy    # ~10-15 min — review plan, then confirm
```

If Terraform gets stuck on VPC/subnet deletion (ENI still attached), force-detach:

```bash
# Find stuck ENIs
aws ec2 describe-network-interfaces --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]" \
  --output table

# Force-detach and delete each stuck ENI
ENI_ID=eni-xxxxxxxxx
aws ec2 detach-network-interface --region us-east-1 \
  --attachment-id $(aws ec2 describe-network-interfaces --region us-east-1 \
    --network-interface-ids $ENI_ID --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text)
sleep 5
aws ec2 delete-network-interface --region us-east-1 --network-interface-id $ENI_ID
```

Then re-run `terraform destroy`.

### Clean up orphaned security groups (if VPC delete hangs)

Sometimes the final blocker is a leftover non-default security group from a Kubernetes ALB.

Check:

```bash
aws ec2 describe-security-groups --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[*].[GroupId,GroupName]" \
  --output table
```

Delete only the non-default groups:

```bash
aws ec2 delete-security-group --region us-east-1 --group-id sg-xxxxxxxx
```

### Clean up orphaned target groups (if any remain)

```bash
for tg_arn in $(AWS_PAGER="" aws elbv2 describe-target-groups --region us-east-1 \
  --query "TargetGroups[*].TargetGroupArn" --output text); do
  aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region us-east-1
done
```

---

## Verification Commands

Run these after destroy to confirm no orphaned resources remain:

```bash
# No EKS cluster
aws eks list-clusters --region us-east-1 --query "clusters"

# No ALBs
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'expense')]"

# No leftover target groups
aws elbv2 describe-target-groups --region us-east-1 \
  --query "TargetGroups[?contains(TargetGroupName, 'expense')]"

# No orphan ENIs in the VPC (VPC should be gone)
aws ec2 describe-vpcs --region us-east-1 \
  --filters "Name=tag:Name,Values=expense-tracker-prod-vpc" \
  --query "Vpcs[*].VpcId"

# No leftover security groups (except default)
aws ec2 describe-security-groups --region us-east-1 \
  --filters "Name=tag:Project,Values=expense-tracker" \
  --query "SecurityGroups[*].[GroupId,GroupName]"

# ECR repos gone
aws ecr describe-repositories --region us-east-1 \
  --query "repositories[?contains(repositoryName, 'expense-tracker')]"

# Secrets Manager — should be empty (recovery_window=0)
aws secretsmanager list-secrets --region us-east-1 \
  --filters Key=name,Values=expense-tracker \
  --query "SecretList[*].Name"

# Terraform state confirms empty
cd Expense-Tracker-Infra/terraform/environments/prod
terraform show   # Should show "No state"
```

---

## Rebuild

After a clean destroy, follow the **Fresh Deploy** procedure in
[Expense-Tracker-App/RUNBOOK.md](../Expense-Tracker-App/RUNBOOK.md#fresh-deploy-from-scratch).

Summary:
1. `terraform apply` (~15 min)
2. Push images to ECR (CI trigger or manual push)
3. Wait for ArgoCD convergence (~5 min)
