output "argocd_namespace" {
  description = "Namespace onde o ArgoCD está instalado"
  value       = "argocd"
}

output "argocd_server" {
  description = "Endpoint do ArgoCD server"
  value       = "https://${var.domain}"
}

output "argocd_helm_version" {
  description = "Versão do Helm chart do ArgoCD"
  value       = var.argocd_version
}

output "appset_infra_name" {
  description = "Nome do ApplicationSet de infraestrutura"
  value       = "infra-apps"
}

output "appset_tenants_name" {
  description = "Nome do ApplicationSet de tenants"
  value       = "tenant-apps"
}
