# ═══════════════════════════════════════════════════════════════
# AMBIENTE: PROD
# ═══════════════════════════════════════════════════════════════
# Orquestra a criacao completa do ambiente multi-tenant.
#
# ORDEM DE EXECUCAO (automatica via depends_on):
#   1. tenant_network  → VPC, subnets, NAT (HA por AZ)
#   2. tenant_eks      → Cluster EKS, node group, IAM roles
#   3. karpenter.tf    → Helm + manifests (se enable_karpenter)
#   4. tenant_argocd   → ArgoCD via Helm
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
    key            = "environments/prod/terraform.tfstate"
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

# ─── Módulo de Rede ──────────────────────────────────────────
module "tenant_network" {
  source = "../../modules/tenant-network"

  tenant      = var.tenant
  environment = var.environment
  vpc         = var.vpc
  tags        = var.tags
}

# ─── Módulo EKS ──────────────────────────────────────────────
module "tenant_eks" {
  source = "../../modules/tenant-eks"

  tenant             = var.tenant
  environment        = var.environment
  vpc_id             = module.tenant_network.vpc_id
  private_subnet_ids = module.tenant_network.private_subnet_ids
  enable_karpenter   = var.enable_karpenter
  tags               = var.tags
}

# ─── Karpenter (Helm + Manifests) ────────────────────────────
# Ver karpenter.tf para detalhes

# ─── ArgoCD ──────────────────────────────────────────────────
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

  depends_on = [module.tenant_eks]
}
