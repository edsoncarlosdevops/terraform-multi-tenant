# ═══════════════════════════════════════════════════════════════
# KARPENTER: Instalação via Helm + Manifests de Configuração
# ═══════════════════════════════════════════════════════════════
# Instala o controller do Karpenter via Helm e configura
# EC2NodeClass e NodePool com APIs v1.
#
# ORDEM:
#   1. helm_release.karpenter_crds  → CRDs do Karpenter
#   2. helm_release.karpenter        → Controller (IRSA via OIDC)
#   3. kubectl_manifest.karpenter_node_class  → EC2NodeClass
#   4. kubectl_manifest.karpenter_node_pool   → NodePool
# ═══════════════════════════════════════════════════════════════

locals {
  karpenter_name_prefix = "${var.tenant}-${var.environment}"
}

# ─── CRDs do Karpenter ────────────────────────────────────────
resource "helm_release" "karpenter_crds" {
  count      = var.enable_karpenter ? 1 : 0
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "1.0.12"
  namespace  = "kube-system"
  create_namespace = true
  wait       = true
  timeout    = 120

  depends_on = [module.tenant_eks]
}

# ─── Aguarda nodes ficarem Ready ──────────────────────────────
resource "time_sleep" "wait_nodes_ready" {
  count      = var.enable_karpenter ? 1 : 0
  depends_on = [module.tenant_eks]
  create_duration = "30s"
}

# ─── Controller do Karpenter ──────────────────────────────────
resource "helm_release" "karpenter" {
  count      = var.enable_karpenter ? 1 : 0
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.12"
  namespace  = "kube-system"
  create_namespace = true
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.tenant_eks.karpenter_controller_role_arn
        }
      }
      settings = {
        clusterName = module.tenant_eks.cluster_name
      }
      controller = {
        resources = {
          requests = { cpu = "1", memory = "1Gi" }
          limits  = { cpu = "1", memory = "1Gi" }
        }
      }
    })
  ]

  depends_on = [
    helm_release.karpenter_crds[0],
    time_sleep.wait_nodes_ready[0],
    module.tenant_eks
  ]
}

# ─── Aguarda controller ficar pronto ──────────────────────────
resource "time_sleep" "wait_karpenter" {
  count      = var.enable_karpenter ? 1 : 0
  depends_on = [helm_release.karpenter[0]]
  create_duration = "15s"
}

# ─── EC2NodeClass: define tipo de máquina ─────────────────────
resource "kubectl_manifest" "karpenter_node_class" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: ${local.karpenter_name_prefix}
spec:
  amiFamily: AL2023
  role: ${module.tenant_eks.karpenter_role_name}
  amiSelectorTerms:
    - alias: al2023@v20250303
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.karpenter_name_prefix}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.karpenter_name_prefix}
  tags:
    Tenant: ${var.tenant}
    Environment: ${var.environment}
    ManagedBy: karpenter
YAML

  depends_on = [
    helm_release.karpenter[0],
    time_sleep.wait_karpenter[0]
  ]
}

# ─── NodePool: regras de escalonamento ────────────────────────
resource "kubectl_manifest" "karpenter_node_pool" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ${local.karpenter_name_prefix}
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: ${local.karpenter_name_prefix}
      requirements:
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: ${jsonencode(var.karpenter_instance_families)}
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
      expireAfter: 720h
  limits:
    cpu: ${var.environment == "dev" ? 2 : 100}
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class[0]
  ]
}
