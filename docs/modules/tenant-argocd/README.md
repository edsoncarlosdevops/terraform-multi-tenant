#  Módulo `tenant-argocd` — GitOps Multi-Tenant

[<- Voltar ao README principal](../../../README.md)

---

##  Visão Geral

O módulo `tenant-argocd` instala o **ArgoCD** via Helm chart e configura **ApplicationSets** para deploy automático de aplicações multi-tenant e componentes de infraestrutura. Implementa **RBAC por tenant** e **AppProjects** para isolamento de segurança.

---

##  Arquivos do Módulo

```
modules/tenant-argocd/
 variables.tf        <- 9 variáveis (contrato do módulo)
 providers.tf        <- Helm + Kubectl + Kubernetes providers
 version.tf          <- Local infra_version para rastreabilidade
 namespace.tf        <- Namespace "argocd" com labels/annotations
 helm-release.tf     <- Helm release do ArgoCD
 values.yaml         <- Values: RBAC, Ingress ALB, Resources
 applicationsets.tf  <- 2 ApplicationSets (tenants + infra)
 projects.tf         <- 2 AppProjects (infra + tenants)
 outputs.tf          <- 5 outputs
```

---

##  Variáveis de Entrada (Contrato)

```hcl
variable "tenant"                              { type = string }                    # "acme-corp"
variable "environment"                         { type = string }                    # "dev"
variable "infra_version"                       { type = string, default = "dev" }   # Tag SemVer
variable "cluster_endpoint"                    { type = string }                    # Do módulo EKS
variable "cluster_certificate_authority_data"  { type = string }                    # Do módulo EKS
variable "cluster_name"                        { type = string }                    # Do módulo EKS
variable "argocd_version"                      { type = string, default = "7.8.0" }
variable "admin_password_hash"                 { type = string, sensitive = true }  # bcrypt hash
variable "domain"                              { type = string, default = "" }      # argocd.acme.com
variable "tags"                                { type = map(string), default = {} }
```

**Nota:** `admin_password_hash` é marcado como `sensitive = true` -> Terraform nunca exibe o valor no log.

---

##  Detalhamento por Arquivo

### 1. `providers.tf` — Configuração de Providers

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"   # <- NÃO é hashicorp/kubectl (que não existe)
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
```

**Por que `gavinbunney/kubectl`?**
- O provider oficial `hashicorp/kubernetes` não suporta CRDs nativamente
- `kubectl_manifest` permite aplicar qualquer YAML (ApplicationSets, NodePools, etc)
- É o padrão de facto na comunidade Terraform para CRDs do K8s

**Os providers são herdados** do ambiente que chama o módulo (ex: `environments/dev/main.tf`). Não precisam ser configurados aqui.

---

### 2. `version.tf` — Rastreabilidade de Versão

```hcl
locals {
  infra_version = try(var.infra_version, "dev")
}
```

**Uso:** Essa versão é injetada como label/annotation em todos os recursos do ArgoCD. Permite responder a pergunta:

> "Qual versão da infraestrutura criou este namespace/deployment?"

No CI/CD, a versão é passada automaticamente:
```bash
export TF_VAR_infra_version=v1.2.3
terraform apply
```

---

### 3. `namespace.tf` — Namespace com Metadata Rico

```hcl
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"

    labels = {
      "istio-injection" = "disabled"      # Evita conflitos com Istio
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
```

**Por que tantos labels/annotations?**
- **Labels** -> Usados para seleção (`kubectl get ns -l tenant=acme-corp`)
- **Annotations** -> Metadata informativo (URL do repo, versão)
- **`istio-injection = disabled`** -> Se Istio for instalado depois, não interfere no ArgoCD

---

### 4. `helm-release.tf` — Instalação do ArgoCD

```hcl
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version     # 7.8.0
  namespace  = "argocd"

  depends_on = [kubernetes_namespace_v1.argocd]

  values = [
    templatefile("${path.module}/values.yaml", {
      admin_password_hash = var.admin_password_hash
      domain              = var.domain
      tenant              = var.tenant
      environment         = var.environment
    })
  ]
}
```

**`templatefile`** -> Renderiza o `values.yaml` substituindo variáveis:
- `${domain}` -> `argocd.acme-corp.com` ou `""`
- `${tenant}` -> `acme-corp`
- `${environment}` -> `dev`
- `${admin_password_hash}` -> Hash bcrypt da senha admin

---

### 5. `values.yaml` — Configuração Customizada do ArgoCD

```yaml
#  Configuração Global 
global:
  domain: ${domain}

configs:
  params:
    server.insecure: true           # <- TLS termina no ALB, não no ArgoCD

  cm:
    admin.enabled: true
    timeout.reconciliation: 60s     # <- Verifica mudanças no Git a cada 60s
    statusbadge.enabled: true       # <- Badges de status nos repos

  #  RBAC: Controle de Acesso por Tenant 
  rbac:
    policy.default: role:readonly   # <- Quem não tem role, só lê
    policy.csv: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, projects, *, *, allow
      p, role:admin, clusters, *, *, allow
      p, role:admin, repositories, *, *, allow
      p, role:admin, logs, *, *, allow
      p, role:admin, exec, *, *, allow
      g, ${tenant}-admin, role:admin   # <- Grupo do tenant tem acesso admin
```

#### RBAC Explicado

```
p, role:admin, applications, *, */*, allow
                                  Ação: permitir
                              Recursos: todos (*/*)
                            Ação: todas (*)
              Recurso tipo: applications
   Role: admin
 p = policy

g, acme-corp-admin, role:admin
                   Mapeia para role:admin
   Grupo: acme-corp-admin (vem do IdP/SSO)
 g = group binding
```

#### Ingress ALB (Condicional)

```yaml
server:
  ingress:
    enabled: ${domain != ""}        # <- Só habilita se tiver domínio
    annotations:
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/tags: >-
        Tenant=${tenant},Environment=${environment},ManagedBy=terraform
```

#### Resource Limits

```yaml
repoServer:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 256Mi }

controller:
  requests: { cpu: 250m, memory: 256Mi }
  limits:   { cpu: 1,    memory: 512Mi }

redis:
  requests: { cpu: 50m,  memory: 64Mi }
  limits:   { cpu: 250m, memory: 128Mi }
```

**Por que definir limits?**
- Evita que um componente consuma todo o CPU/memória do node
- Importante em ambientes compartilhados (multi-tenant)
- Em dev com Karpenter limit de 2 vCPU, cada milicore conta

---

### 6. `applicationsets.tf` — 2 ApplicationSets

#### ApplicationSet 1: `tenant-apps` (Generator: Git)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/${tenant}/saas-platform.git
        revision: HEAD
        directories:
          - path: tenants/*        # <- Cada pasta = 1 Application
  template:
    metadata:
      name: '{{path.basename}}'    # <- Nome do diretório vira nome do app
      labels:
        tenant: '{{path.basename}}'
        environment: '${environment}'
    spec:
      source:
        repoURL: https://github.com/${tenant}/saas-platform.git
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true              # <- Remove recursos deletados do Git
          selfHeal: true           # <- Corrige drifts automaticamente
        syncOptions:
          - CreateNamespace=true   # <- Cria namespace se não existir
          - PruneLast=true         # <- Deleta por último (segurança)
```

**Como funciona:**

```
repositório Git:
  saas-platform/
   tenants/
       customer-a/        ->  Application: customer-a (namespace: customer-a)
          deployment.yaml
          service.yaml
       customer-b/        ->  Application: customer-b (namespace: customer-b)
          kustomization.yaml
       customer-c/        ->  Application: customer-c (namespace: customer-c)
           helm/Chart.yaml
```

**Onboarding de novo tenant:** Basta criar uma pasta em `tenants/` no Git -> ArgoCD cria tudo automaticamente.

#### ApplicationSet 2: `infra-apps` (Generator: List)

```yaml
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
```

**Estes são os componentes base** que toda infraestrutura Kubernetes precisa:

| Componente | Função |
|-----------|--------|
| **ingress-nginx** | Ingress controller (roteamento HTTP/HTTPS) |
| **cert-manager** | Certificados TLS automáticos (Let's Encrypt) |
| **metrics-server** | Métricas de CPU/memória para HPA |
| **cluster-autoscaler** | Auto-scaling de nodes (backup do Karpenter) |
| **aws-load-balancer-controller** | Provisiona ALB/NLB automaticamente |

---

### 7. `projects.tf` — 2 AppProjects (Isolamento)

#### AppProject: `infra`

```yaml
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
    - namespace: 'cert-manager'
    - namespace: 'kube-system'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'           # <- Pode criar CRDs, ClusterRoles, etc.
```

#### AppProject: `tenants`

```yaml
spec:
  description: "Projetos dos tenants — com restrições de segurança"
  sourceRepos:
    - 'https://github.com/${tenant}/saas-platform.git'
  destinations:
    - namespace: '*'       # <- Qualquer namespace
  clusterResourceWhitelist:
    - group: ''
      kind: 'Namespace'
      kind: 'ResourceQuota'
      kind: 'LimitRange'   # <- APENAS estes cluster resources
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'            # <- Dentro do namespace, pode tudo
```

**Segurança do isolamento:**

```
 AppProject: infra 
  Pode criar: CRDs, ClusterRoles, etc.         
  Repos: apenas Helm charts oficiais            
  Namespaces: ingress-nginx, cert-manager, etc. 
  Não pode: acessar namespaces de tenants       


 AppProject: tenants 
  Pode criar: Deployments, Services, etc.       
  Pode criar: Namespaces, ResourceQuotas         
  Não pode: criar CRDs, ClusterRoles             
  Não pode: acessar outros repos                  
 -> Isolamento zero-trust por projeto              

```

---

### 8. `outputs.tf`

```hcl
output "argocd_namespace"      # "argocd"
output "argocd_server"         # "https://argocd.acme-corp.com"
output "argocd_helm_version"   # "7.8.0"
output "appset_infra_name"     # "infra-apps"
output "appset_tenants_name"   # "tenant-apps"
```

---

##  Diagrama do ArgoCD

```
 ArgoCD 
                                                                         
    Helm Release (argo-cd 7.8.0)  
     Server    Controller    RepoServer    Redis    AppSet Ctrl  
    
                                                                         
    AppProject: infra    AppProject: tenants  
     Repos: Helm charts oficiais    Repos: github.com/${tenant}   
     NS: ingress, cert-mgr...      NS: * (com restrições)         
      
                                                                       
      
     ApplicationSet: infra-apps      ApplicationSet: tenant-apps   
     Generator: LIST                 Generator: GIT (directories)  
                                                                    
     -> ingress-nginx    4.12.0       -> tenants/customer-a/         
     -> cert-manager     1.17.0       -> tenants/customer-b/         
     -> metrics-server   3.12.2       -> tenants/customer-c/         
     -> cluster-autoscaler 9.46.0     -> (auto-detecta novas pastas) 
     -> aws-lb-controller 1.10.1                                     
      
                                                                         
    RBAC   
     Default: role:readonly (todos vêem, ninguém mexe)                
     ${tenant}-admin -> role:admin (acesso total ao tenant)            
     

```

---

##  Exemplo de Uso

```hcl
module "tenant_argocd" {
  source = "../../modules/tenant-argocd"

  tenant                             = "acme-corp"
  environment                        = "dev"
  infra_version                      = "v1.2.3"
  cluster_endpoint                   = module.tenant_eks.cluster_endpoint
  cluster_certificate_authority_data = module.tenant_eks.cluster_certificate_authority_data
  cluster_name                       = module.tenant_eks.cluster_name
  domain                             = "argocd.acme-corp.dev"  # "" para desabilitar Ingress
  
  tags = { CostCenter = "engineering" }
}
```

---

##  Conceitos para Estudar

| Conceito | O que é | Relevância |
|---------|---------|-----------|
| **ArgoCD** | Ferramenta GitOps para Kubernetes | Deploy contínuo declarativo |
| **ApplicationSet** | Gera Applications automaticamente | Multi-tenant automation |
| **AppProject** | Isolamento de RBAC no ArgoCD | Segurança por tenant |
| **Helm** | Package manager para Kubernetes | Instalação de componentes |
| **GitOps** | Estado desejado definido no Git | Infraestrutura como código |
| **Self-Heal** | ArgoCD corrige drifts automaticamente | Resiliência |
| **Prune** | Remove recursos deletados do Git | Limpeza automática |
| **CRDs** | Custom Resource Definitions | Extensão do K8s |
| **RBAC** | Role-Based Access Control | Controle de acesso |
| **ALB Ingress** | AWS Application Load Balancer via Ingress | Exposição de serviços |

---

[<- Voltar ao README principal](../../../README.md)
