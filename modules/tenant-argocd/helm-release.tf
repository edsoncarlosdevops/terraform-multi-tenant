# ─── Instalação do ArgoCD via Helm ───────────────────────────
resource "helm_release" "argocd" {
  provider = helm.eks

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = "argocd"

  depends_on = [kubernetes_namespace_v1.argocd]

  values = [
    templatefile("${path.module}/values.yaml", {
      admin_password_hash = var.admin_password_hash
      domain              = var.domain
      tenant              = var.tenant
      environment         = var.environment
    })
  ]
}
