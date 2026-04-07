# Ephemeral Secrets
#
# All secrets are managed by this stack and destroyed with it.
# recovery_window_in_days = 0 ensures immediate deletion on terraform destroy,
# allowing clean destroy/apply cycles with zero manual steps.
#
# External credentials (OAuth, GitHub App key) are passed via Terraform variables.
# Internal credentials (Grafana admin password) are auto-generated.
#
# Secret paths match what ExternalSecrets/ArgoCD expect — no GitOps changes needed.

# ─────────────────────────────────────────────────
# Auto-generated Credentials
# ─────────────────────────────────────────────────

resource "random_password" "grafana_admin" {
  length           = 24
  special          = true
  override_special = "!@#$%&"
}

resource "random_password" "postgres_app_prod" {
  length           = 24
  special          = true
  override_special = "!@#$%&"
}

resource "random_password" "postgres_admin_prod" {
  length           = 24
  special          = true
  override_special = "!@#$%&"
}

resource "random_password" "postgres_app_staging" {
  length           = 24
  special          = true
  override_special = "!@#$%&"
}

resource "random_password" "postgres_admin_staging" {
  length           = 24
  special          = true
  override_special = "!@#$%&"
}

# ─────────────────────────────────────────────────
# GitHub App Private Key (ArgoCD repo access)
# ─────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "github_app_key" {
  name                    = "argocd/github-app-private-key"
  description             = "GitHub App private key for ArgoCD repo access"
  recovery_window_in_days = 0

  tags = {
    Component = "argocd"
    Layer     = "ephemeral"
  }
}

resource "aws_secretsmanager_secret_version" "github_app_key" {
  secret_id     = aws_secretsmanager_secret.github_app_key.id
  secret_string = var.github_app_private_key
}

# ─────────────────────────────────────────────────
# Grafana Admin Credentials (auto-generated)
# ─────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${var.project_name}/${var.environment}/grafana/admin-credentials"
  description             = "Grafana admin username and password"
  recovery_window_in_days = 0

  tags = {
    Component = "monitoring"
    Layer     = "ephemeral"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin.result
  })
}

# ─────────────────────────────────────────────────
# Grafana OIDC Credentials (Google OAuth)
# ─────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "grafana_oidc" {
  name                    = "${var.project_name}/${var.environment}/grafana/oidc-credentials"
  description             = "Google OAuth client credentials for Grafana SSO"
  recovery_window_in_days = 0

  tags = {
    Component = "monitoring"
    Layer     = "ephemeral"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_oidc" {
  secret_id = aws_secretsmanager_secret.grafana_oidc.id
  secret_string = jsonencode({
    client_id     = var.grafana_oauth_client_id
    client_secret = var.grafana_oauth_client_secret
  })
}

# ─────────────────────────────────────────────────
# ArgoCD OIDC Credentials (Google OAuth)
# ─────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "argocd_oidc" {
  name                    = "${var.project_name}/${var.environment}/argocd/oidc-credentials"
  description             = "Google OAuth client credentials for ArgoCD SSO"
  recovery_window_in_days = 0

  tags = {
    Component = "argocd"
    Layer     = "ephemeral"
  }
}

resource "aws_secretsmanager_secret_version" "argocd_oidc" {
  secret_id = aws_secretsmanager_secret.argocd_oidc.id
  secret_string = jsonencode({
    client_id     = var.argocd_oauth_client_id
    client_secret = var.argocd_oauth_client_secret
  })
}

# ─────────────────────────────────────────────────
# PostgreSQL Credentials (prod + staging)
# ─────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "postgresql_prod" {
  name                    = "${var.project_name}/${var.environment}/postgresql/auth"
  description             = "Bitnami PostgreSQL credentials for the production database"
  recovery_window_in_days = 0

  tags = {
    Component = "database"
    Layer     = "ephemeral"
  }
}

resource "aws_secretsmanager_secret_version" "postgresql_prod" {
  secret_id = aws_secretsmanager_secret.postgresql_prod.id
  secret_string = jsonencode({
    password            = random_password.postgres_app_prod.result
    "postgres-password" = random_password.postgres_admin_prod.result
  })
}

resource "aws_secretsmanager_secret" "postgresql_staging" {
  name                    = "${var.project_name}/staging/postgresql/auth"
  description             = "Bitnami PostgreSQL credentials for the staging database"
  recovery_window_in_days = 0

  tags = {
    Component = "database"
    Layer     = "ephemeral"
  }
}

resource "aws_secretsmanager_secret_version" "postgresql_staging" {
  secret_id = aws_secretsmanager_secret.postgresql_staging.id
  secret_string = jsonencode({
    password            = random_password.postgres_app_staging.result
    "postgres-password" = random_password.postgres_admin_staging.result
  })
}
