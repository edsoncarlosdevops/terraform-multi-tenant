# ═══════════════════════════════════════════════════════════════
# PROVIDERS + DATA SOURCES
# ═══════════════════════════════════════════════════════════════
# ATENCAO: Providers kubectl/helm/kubernetes SO funcionam
# DEPOIS que o cluster EKS estiver ACTIVE.
# Eles dependem de module.tenant_eks (resolvido via data source).
# ═══════════════════════════════════════════════════════════════

data "aws_eks_cluster_auth" "this" {
  name = module.tenant_eks.cluster_name
}

provider "kubectl" {
  host                   = module.tenant_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = module.tenant_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = module.tenant_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
