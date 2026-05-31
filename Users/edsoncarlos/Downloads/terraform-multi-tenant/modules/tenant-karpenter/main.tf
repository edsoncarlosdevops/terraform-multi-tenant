# ═══════════════════════════════════════════════════════════════
# KARPENTER CONTROLLER: Instalação via Helm
# ═══════════════════════════════════════════════════════════════
# Este módulo instala o controller do Karpenter e seus CRDs
# no cluster EKS usando o Helm provider do Terraform.
#
# IMPORTANTE: O cluster EKS precisa estar ACTIVE antes de
# executar este módulo. Use depends_on para garantir.
# ═══════════════════════════════════════════════════════════════

locals {
  name_prefix = "${var.tenant}-${var.environment}"
}

# ─── Helm Release: CRDs do Karpenter ──────────────────────────
resource "helm_release" "karpenter_crds" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_version
  namespace  = var.karpenter_namespace

  # CRDs são cluster-scoped, sem dependências
  create_namespace = true
  wait             = true

  # Timeout maior para garantir que tudo seja aplicado
  timeout = 120
}

# ─── Helm Release: Controller do Karpenter ────────────────────
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  namespace  = var.karpenter_namespace

  create_namespace = true
  wait             = true
  timeout          = 180

  values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.karpenter_role_arn
        }
      }
      settings = {
        clusterName = var.cluster_name
      }
      controller = {
        resources = {
          requests = {
            cpu    = "1"
            memory = "1Gi"
          }
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    })
  ]

  depends_on = [
    helm_release.karpenter_crds
  ]
}

# ─── Aguardar CRDs ficarem disponíveis ────────────────────────
resource "time_sleep" "wait_for_crds" {
  depends_on = [
    helm_release.karpenter
  ]

  create_duration = "10s"
}
