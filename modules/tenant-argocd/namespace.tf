#  Namespace dedicado para ArgoCD 
# ATENCAO: O ArgoCD ApplicationSets/Applications criam finalizers
# nos recursos gerenciados. Durante o destroy, o namespace fica
# preso em Terminating se os finalizers nao forem removidos antes.
#
# A ordem de destruicao e:
#   1. kubectl_manifest (ApplicationSets, AppProjects)
#   2. helm_release.argocd
#   3. null_resource.cleanup_argocd_finalizers (remove finalizers)
#   4. kubernetes_namespace_v1.argocd (namespace)
resource "kubernetes_namespace_v1" "argocd" {

  metadata {
    name = "argocd"

    labels = {
      "istio-injection" = "disabled"
      "tenant"          = var.tenant
      "environment"     = var.environment
      "managed-by"      = "terraform"
      "infra-version"   = var.infra_version
    }

    annotations = {
      "infra.tenant.io/version"     = var.infra_version
      "infra.tenant.io/environment" = var.environment
      "infra.tenant.io/tenant"      = var.tenant
      "infra.tenant.io/repo"        = "https://github.com/${var.tenant}/saas-platform"
    }
  }
}

#  Remove finalizers do ArgoCD antes de destruir o namespace 
# Necessario para evitar que o namespace fique preso em Terminating
# O depends_on garante que o cleanup rode DEPOIS do helm_release
# ser destruido, mas ANTES do namespace ser destruido.
resource "null_resource" "cleanup_argocd_finalizers" {
  triggers = {
    namespace = kubernetes_namespace_v1.argocd.id
  }

  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
      echo "=== Removendo finalizers do ArgoCD ==="
      
      # Aguarda o Helm release ser completamente removido
      sleep 10
      
      # Remove finalizers de Applications
      kubectl get applications -A -o name 2>/dev/null | xargs -r -I{} sh -c 'kubectl patch {} --type=merge -p "{\"metadata\":{\"finalizers\":[]}}" 2>/dev/null || true' || true
      
      # Remove finalizers de ApplicationSets
      kubectl get applicationsets -A -o name 2>/dev/null | xargs -r -I{} sh -c 'kubectl patch {} --type=merge -p "{\"metadata\":{\"finalizers\":[]}}" 2>/dev/null || true' || true
      
      # Remove finalizers de AppProjects
      kubectl get appprojects -A -o name 2>/dev/null | xargs -r -I{} sh -c 'kubectl patch {} --type=merge -p "{\"metadata\":{\"finalizers\":[]}}" 2>/dev/null || true' || true
      
      # Remove finalizers de qualquer AppProject no namespace argocd
      kubectl get appproject -n argocd -o name 2>/dev/null | xargs -r -I{} sh -c 'kubectl patch {} --type=merge -p "{\"metadata\":{\"finalizers\":[]}}" 2>/dev/null || true' || true
      
      echo "=== Finalizers removidos. Aguardando 10s para propagacao ==="
      sleep 10
    EOF
  }
}
