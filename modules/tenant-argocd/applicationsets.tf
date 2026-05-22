# ─── ApplicationSet Multi-Tenant ─────────────────────────────
# Cria um ApplicationSet que gera Applications para cada tenant
# baseado em um arquivo JSON/ YAML no repositório Git

resource "kubectl_manifest" "appset_tenants" {

  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/${var.tenant}/saas-platform.git
        revision: HEAD
        directories:
          - path: tenants/*
  template:
    metadata:
      name: '{{path.basename}}'
      labels:
        tenant: '{{path.basename}}'
        environment: '${var.environment}'
    spec:
      project: default
      source:
        repoURL: https://github.com/${var.tenant}/saas-platform.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - PruneLast=true
YAML

  depends_on = [helm_release.argocd]
}

# ─── ApplicationSet para Infraestrutura Base ─────────────────
# Instala componentes compartilhados: ingress-nginx, cert-manager,
# metrics-server, cluster-autoscaler, etc.

resource "kubectl_manifest" "appset_infra" {

  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infra-apps
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - name: ingress-nginx
            repo: https://kubernetes.github.io/ingress-nginx
            chart: ingress-nginx
            version: 4.12.0
            namespace: ingress-nginx
          - name: cert-manager
            repo: https://charts.jetstack.io
            chart: cert-manager
            version: 1.17.0
            namespace: cert-manager
          - name: metrics-server
            repo: https://kubernetes-sigs.github.io/metrics-server/
            chart: metrics-server
            version: 3.12.2
            namespace: kube-system
          - name: cluster-autoscaler
            repo: https://kubernetes.github.io/autoscaler
            chart: cluster-autoscaler
            version: 9.46.0
            namespace: kube-system
          - name: aws-load-balancer-controller
            repo: https://aws.github.io/eks-charts
            chart: aws-load-balancer-controller
            version: 1.10.1
            namespace: kube-system
  template:
    metadata:
      name: '{{name}}'
      labels:
        app: '{{name}}'
        tier: infra
    spec:
      project: infra
      source:
        repoURL: '{{repo}}'
        chart: '{{chart}}'
        targetRevision: '{{version}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
YAML

  depends_on = [helm_release.argocd]
}
