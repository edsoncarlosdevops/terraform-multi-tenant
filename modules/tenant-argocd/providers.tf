# ─── Providers para interagir com o cluster EKS ──────────────
# Configurados separadamente para evitar conflito com providers
# do ambiente que chama o módulo

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "helm" {
  alias = "eks"

  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  alias = "eks"

  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}
