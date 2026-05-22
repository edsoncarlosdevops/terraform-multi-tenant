# ─── Namespace dedicado para ArgoCD ──────────────────────────
resource "kubernetes_namespace_v1" "argocd" {
  provider = helm.eks

  metadata {
    name = "argocd"

    labels = {
      "istio-injection" = "disabled"
      "tenant"          = var.tenant
      "environment"     = var.environment
      "managed-by"      = "terraform"
      "infra-version"   = var.infra_version
    }

    annotations = {
      "infra.tenant.io/version"     = var.infra_version
      "infra.tenant.io/environment" = var.environment
      "infra.tenant.io/tenant"      = var.tenant
      "infra.tenant.io/repo"        = "https://github.com/${var.tenant}/saas-platform"
    }
  }
}

