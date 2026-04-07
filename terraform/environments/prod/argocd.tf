# ArgoCD - Declarative Bootstrap via Terraform
# Installs ArgoCD, creates GitHub App repo credentials, and deploys root app-of-apps.
# Zero manual steps required after terraform apply.

# Install ArgoCD via Helm
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  # Base ArgoCD values (inline to avoid cross-repo file dependencies)
  values = [
    yamlencode({
      server = {
        extraArgs = ["--insecure"]
        replicas  = 1
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
        service = { type = "ClusterIP" }
        ingress = {
          enabled          = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"          = "ip"
            "alb.ingress.kubernetes.io/listen-ports"         = "[{\"HTTPS\":443}]"
            "alb.ingress.kubernetes.io/ssl-policy"           = "ELBSecurityPolicy-TLS13-1-2-2021-06"
            "alb.ingress.kubernetes.io/inbound-cidrs"        = "203.0.113.10/32"
            "alb.ingress.kubernetes.io/group.name"           = "expense-tracker-ops"
            "alb.ingress.kubernetes.io/group.order"          = "10"
            "alb.ingress.kubernetes.io/healthcheck-path"     = "/healthz"
            "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
            "alb.ingress.kubernetes.io/backend-protocol"     = "HTTP"
            "external-dns.alpha.kubernetes.io/hostname"      = "argocd.prod.roctl23.online"
          }
          hostname = "argocd.prod.roctl23.online"
          tls      = true
        }
      }
      controller = {
        replicas = 1
        resources = {
          requests = { cpu = "250m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "1Gi" }
        }
      }
      repoServer = {
        replicas = 1
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "1536Mi" }
        }
      }
      dex = {
        enabled = true
        resources = {
          requests = { cpu = "25m", memory = "64Mi" }
          limits   = { cpu = "100m", memory = "128Mi" }
        }
      }
      redis = {
        enabled = true
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "128Mi" }
        }
      }
      applicationSet = {
        enabled   = true
        resources = { requests = { cpu = "50m", memory = "64Mi" } }
      }
      notifications = { enabled = false }
      configs = {
        ssh = {
          knownHosts = <<-EOT
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
            github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
            github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
          EOT
        }
        params = {
          "server.insecure" = true
        }
        repositories = {}
      }
    })
  ]

  depends_on = [
    module.eks,
    aws_eks_pod_identity_association.aws_lb_controller,
    aws_eks_pod_identity_association.external_secrets,
    aws_eks_pod_identity_association.external_dns,
    aws_eks_pod_identity_association.cert_manager,
  ]
}

# GitHub App repository credentials secret for ArgoCD
resource "kubernetes_secret" "argocd_repo_creds" {
  metadata {
    name      = "github-app-repo-creds"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type                    = "git"
    url                     = "https://github.com/${var.github_org}"
    githubAppID             = var.github_app_id
    githubAppInstallationID = var.github_app_installation_id
    githubAppPrivateKey     = var.github_app_private_key
  }

  type = "Opaque"

  depends_on = [helm_release.argocd]
}

# Root App-of-Apps - the single entry point for all GitOps-managed applications
resource "kubectl_manifest" "root_apps" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root-apps
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/${var.github_org}/Expense-Tracker-gitops-Public.git
        targetRevision: main
        path: apps
        helm:
          valueFiles:
            - values-prod.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
  YAML

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.argocd_repo_creds,
  ]
}
