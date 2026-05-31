#  Providers necessários para o módulo EKS 
# Declaramos o provider kubectl aqui para que o módulo
# saiba que os manifests usam gavinbunney/kubectl
# e não o hashicorp/kubectl (que não existe)

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}
