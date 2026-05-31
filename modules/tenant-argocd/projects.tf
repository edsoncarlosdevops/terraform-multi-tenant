#  AppProject para Infraestrutura Compartilhada 
resource "kubectl_manifest" "project_infra" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infra
  namespace: argocd
spec:
  description: "Projeto de infraestrutura compartilhada"
  sourceRepos:
    - 'https://kubernetes.github.io/ingress-nginx'
    - 'https://charts.jetstack.io'
    - 'https://kubernetes-sigs.github.io/metrics-server/'
    - 'https://kubernetes.github.io/autoscaler'
    - 'https://aws.github.io/eks-charts'
  destinations:
    - namespace: 'ingress-nginx'
      server: https://kubernetes.default.svc
    - namespace: 'cert-manager'
      server: https://kubernetes.default.svc
    - namespace: 'kube-system'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  orphanedResources:
    warn: true
YAML

  depends_on = [helm_release.argocd]
}

#  AppProject para cada Tenant (isolamento) 
resource "kubectl_manifest" "project_tenants" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: tenants
  namespace: argocd
spec:
  description: "Projetos dos tenants — com restrições de segurança"
  sourceRepos:
    - 'https://github.com/${var.tenant}/saas-platform.git'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: 'Namespace'
      kind: 'ResourceQuota'
      kind: 'LimitRange'
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  orphanedResources:
    warn: true
YAML

  depends_on = [helm_release.argocd]
}
