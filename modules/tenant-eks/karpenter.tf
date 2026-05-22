# ═══════════════════════════════════════════════════════════════
# KARPENTER: Escalonamento Inteligente de Nos
# ═══════════════════════════════════════════════════════════════
# Como funciona:
# 1. EC2NodeClass   → define o "tipo" de maquina (AMI, role, subnets)
# 2. NodePool       → define as regras de escalonamento (familia, spot, limites)
# 3. Subnet tags    → permite o Karpenter descobrir as subnets
#
# IMPORTANTE: O controller do Karpenter precisa ser instalado SEPARADAMENTE
# via Helm chart (nao via Terraform). Isso e feito manualmente ou via ArgoCD.
# Estes manifests APENAS configuram o controller DEPOIS de instalado.
#
# Se der erro "no matches for kind EC2NodeClass":
#   → O controller do Karpenter nao foi instalado ainda
#   → Solucao: instale o helm chart primeiro (veja scripts/test-full.sh)
# ═══════════════════════════════════════════════════════════════

resource "kubectl_manifest" "karpenter_node_class" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: ${local.name_prefix}
spec:
  amiFamily: AL2
  role: ${aws_iam_role.karpenter[0].name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.name_prefix}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.name_prefix}
  tags:
    Tenant: ${var.tenant}
    Environment: ${var.environment}
    ManagedBy: karpenter
YAML

  depends_on = [
    aws_eks_cluster.this,
    null_resource.wait_for_cluster
  ]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<YAML
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: ${local.name_prefix}
spec:
  template:
    spec:
      nodeClassRef:
        name: ${local.name_prefix}
      requirements:
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: ${jsonencode(var.karpenter_instance_families)}
        # ─── Em dev: prioriza SPOT (mais barato) ──────────────
        # Em prod: permite spot + on-demand
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
  # ─── LIMITE DE CPU ──────────────────────────────────────────
  # Dev: max 2 vCPU (evita gastos surpresa durante testes)
  # Prod: max 100 vCPU (ajuste conforme necessidade)
  limits:
    cpu: ${var.environment == "dev" ? 2 : 100}
  # ─── CONSOLIDACAO ───────────────────────────────────────────
  # WhenUnderutilized → Karpenter remove nos ociosos automaticamente
  # ExpireAfter 720h → nodes sao reciclados a cada 30 dias
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
YAML

  depends_on = [
    aws_eks_cluster.this,
    null_resource.wait_for_cluster
  ]
}

# ─── Tags nas subnets para o Karpenter descobrir ────────────
# Sem isso, o Karpenter nao sabe em quais subnets criar os nodes
resource "aws_ec2_tag" "karpenter_subnets" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.key
  key         = "karpenter.sh/discovery"
  value       = local.name_prefix
}

