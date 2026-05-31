output "argocd_namespace" {
  description = "Namespace onde o ArgoCD está instalado"
  value       = "argocd"
}

output "argocd_server" {
  description = "Endpoint do ArgoCD server"
  value       = var.domain != "" ? "https://${var.domain}" : "http://localhost:8080"
}

output "argocd_helm_version" {
  description = "Versão do Helm chart do ArgoCD"
  value       = var.argocd_version
}

output "argocd_initial_password" {
  description = "Comando para obter a senha inicial do admin do ArgoCD"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d"
}

output "argocd_login_command" {
  description = "Comando para fazer port-forward e logar no ArgoCD"
  value       = <<-EOF
    # Terminal 1: port-forward
    kubectl port-forward svc/argocd-server -n argocd 8080:443

    # Terminal 2: pegar a senha e logar
    PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d)
    echo "Senha: $PASS"
    argocd login localhost:8080 --username admin --password $PASS --insecure
  EOF
}

output "appset_infra_name" {
  description = "Nome do ApplicationSet de infraestrutura"
  value       = "infra-apps"
}

output "appset_tenants_name" {
  description = "Nome do ApplicationSet de tenants"
  value       = "tenant-apps"
}
