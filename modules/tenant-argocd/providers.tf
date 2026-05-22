# ─── Providers necessários para o módulo ArgoCD ─────────────
# Declaramos os providers aqui para que o Terraform saiba
# que os recursos (kubectl_manifest, helm_release, kubernetes_namespace)
# vêm destas fontes, não do hashicorp/kubectl (que não existe)

terraform {
  required_version = ">= 1.6"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}

# ─── Providers vazios ───────────────────────────────────────────
# Os providers (helm, kubernetes, kubectl) são herdados do
# ambiente que chama este módulo (environments/dev/main.tf)
# Não é necessário configurar instâncias aqui.

