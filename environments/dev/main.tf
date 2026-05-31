# ═══════════════════════════════════════════════════════════════
# AMBIENTE: DEV
# ═══════════════════════════════════════════════════════════════
# Este arquivo orquestra a criacao completa de um ambiente
# multi-tenant com VPC, EKS, Karpenter e ArgoCD.
#
# ORDEM DE EXECUCAO RECOMENDADA (evita erros):
#   Apply #1: terraform apply -target=module.tenant_network \
#                               -target=module.tenant_eks
#   ⏳ Aguarda ~15 min o cluster EKS ficar ACTIVE
#   Apply #2: terraform apply (instala Karpenter + ArgoCD)
#
# IMPORTANTE: Em dev, o NAT Gateway esta desligado (economia).
# Sem NAT, recursos em subnets privadas nao tem acesso a internet.
# Para testes basicos com EKS isso nao e problema.
# ═══════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  backend "s3" {
    bucket         = "tfstate-saas-multi-tenant"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-lock"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = var.tags
  }
}

# ─── Provider kubectl configurado para o cluster EKS ────────
# ATENCAO: Esse provider SO funciona DEPOIS que o cluster EKS
# estiver ACTIVE e o wait_for_cluster tiver completado.
# Se der erro de conexao, o cluster ainda nao esta pronto.
provider "kubectl" {
  host                   = module.tenant_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

data "aws_eks_cluster_auth" "this" {
  name = module.tenant_eks.cluster_name
}

# Providers SO funcionam depois do cluster estar ACTIVE
# O data.aws_eks_cluster_auth só é resolvido após wait_for_cluster
# Por isso usamos depends_on implícito via module.tenant_eks

# ─── Provider Helm configurado para o cluster EKS ──────────
provider "helm" {
  kubernetes {
    host                   = module.tenant_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# ─── Provider Kubernetes padrão (para namespaces, etc) ─────
provider "kubernetes" {
  host                   = module.tenant_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# ─── Módulo de Rede (VPC + subnets + NAT + endpoints) ───────
# Cria a infraestrutura de rede basica para o tenant.
# Em DEV: sem NAT Gateway, sem Flow Logs, sem VPC Endpoints Interface.
# Custo: $0/mes
module "tenant_network" {
  source = "../../modules/tenant-network"

  tenant      = var.tenant
  environment = var.environment
  vpc         = var.vpc
  tags        = var.tags
}

# ─── Módulo EKS (Cluster + NodeGroup + Karpenter) ──────────
# Cria o cluster Kubernetes gerenciado pela AWS.
# Inclui IAM Roles, KMS Key, CloudWatch Logs e Security Groups.
# O wait_for_cluster impede que Karpenter/ArgoCD tentem
# instalar antes do cluster estar pronto.
module "tenant_eks" {
  source = "../../modules/tenant-eks"

  tenant             = var.tenant
  environment        = var.environment
  vpc_id             = module.tenant_network.vpc_id
  private_subnet_ids = module.tenant_network.private_subnet_ids
  enable_karpenter   = var.enable_karpenter
  tags               = var.tags
}

# ─── Helm Release: Karpenter Controller ──────────────────────
# Instala o controller do Karpenter e seus CRDs via Helm.
# Executa APÓS o cluster EKS estar operacional.
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

resource "time_sleep" "wait_nodes_ready" {
  count      = var.enable_karpenter ? 1 : 0
  depends_on = [module.tenant_eks]
  create_duration = "30s"
}

resource "helm_release" "karpenter" {
  count      = var.enable_karpenter ? 1 : 0
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.12"
  namespace  = "kube-system"
  create_namespace = true
  wait       = true
  timeout    = 300  # 5 minutos para baixar imagem e iniciar

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

resource "time_sleep" "wait_karpenter" {
  count      = var.enable_karpenter ? 1 : 0
  depends_on = [helm_release.karpenter[0]]
  create_duration = "15s"
}

# ─── Manifests do Karpenter (EC2NodeClass + NodePool) ────────
# Estes recursos configuram o comportamente do Karpenter.
# Precisam ser criados DEPOIS do controller estar instalado.
locals {
  karpenter_name_prefix = "${var.tenant}-${var.environment}"
}

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

# ─── Módulo ArgoCD (GitOps + ApplicationSets) ───────────────
# Instala o ArgoCD via Helm chart e configura:
# - ApplicationSets para infraestrutura base (ingress, cert-manager, etc)
# - ApplicationSets para tenants (multi-tenant)
# - AppProjects com isolamento de RBAC
# - Versionamento (infra_version) nos labels
#
# Depende do EKS estar operacional (wait_for_cluster)
# IMPORTANTE: depends_on no node group garante que os nodes estao READY
module "tenant_argocd" {
  source = "../../modules/tenant-argocd"

  tenant                             = var.tenant
  environment                        = var.environment
  infra_version                      = var.infra_version
  cluster_endpoint                   = module.tenant_eks.cluster_endpoint
  cluster_certificate_authority_data = module.tenant_eks.cluster_certificate_authority_data
  cluster_name                       = module.tenant_eks.cluster_name
  domain                             = var.argocd_domain
  tags                               = var.tags

  depends_on = [
    module.tenant_eks
  ]
}
