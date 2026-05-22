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

# ─── Módulo ArgoCD (GitOps + ApplicationSets) ───────────────
# Instala o ArgoCD via Helm chart e configura:
# - ApplicationSets para infraestrutura base (ingress, cert-manager, etc)
# - ApplicationSets para tenants (multi-tenant)
# - AppProjects com isolamento de RBAC
# - Versionamento (infra_version) nos labels
#
# Depende do EKS estar operacional (wait_for_cluster)
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
}