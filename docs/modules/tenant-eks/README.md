# ️ Módulo `tenant-eks` — Cluster Kubernetes Gerenciado

[← Voltar ao README principal](../../../README.md)

---

##  Visão Geral

O módulo `tenant-eks` cria um **cluster EKS completo** com Node Groups, Karpenter para escalonamento inteligente, IAM Roles com mínimo privilégio, criptografia KMS e mecanismo de espera para garantir que o cluster esteja operacional antes de instalar componentes adicionais.

---

##  Arquivos do Módulo

```
modules/tenant-eks/
├── main.tf               ← Cluster EKS + KMS Key + CloudWatch + Security Group
├── variables.tf          ← 14 variáveis (contrato do módulo)
├── providers.tf          ← Provider kubectl (gavinbunney)
├── iam.tf                ← 3 IAM Roles (cluster, node, karpenter)
├── node-group.tf         ← Node Group On-Demand principal
├── karpenter.tf          ← EC2NodeClass + NodePool + Subnet Tags
├── wait-for-cluster.tf   ← Aguarda cluster ACTIVE + nodes READY
└── outputs.tf            ← 9 outputs
```

---

##  Variáveis de Entrada (Contrato)

```hcl
variable "tenant"                      { type = string }                    # "acme-corp"
variable "environment"                 { type = string }                    # "dev"
variable "vpc_id"                      { type = string }                    # Da saída do tenant-network
variable "private_subnet_ids"          { type = list(string) }             # Da saída do tenant-network
variable "kubernetes_version"          { type = string, default = "1.31" }
variable "node_instance_types"         { type = list(string), default = ["m6i.large", "m6a.large"] }
variable "node_disk_size"              { type = number, default = 50 }      # GB
variable "node_desired_size"           { type = number, default = 2 }
variable "node_min_size"               { type = number, default = 1 }
variable "node_max_size"               { type = number, default = 6 }
variable "enable_karpenter"            { type = bool, default = true }
variable "karpenter_instance_families" { type = list(string), default = ["m6i","m6a","m7i","c6i","c7i","r6i"] }
variable "tags"                        { type = map(string), default = {} }
```

**Por que 14 variáveis?**
- Equilíbrio entre **flexibilidade** (pode customizar tudo) e **defaults inteligentes** (funciona sem configurar nada)
- Em dev, os defaults já são otimizados para custo baixo

---

##  Detalhamento por Arquivo

### 1. `main.tf` — Cluster EKS

> ️ **ATENÇÃO:** O cluster EKS leva **10-15 minutos** para ficar ACTIVE!

```hcl
resource "aws_eks_cluster" "this" {
  name     = "${local.name_prefix}-eks"      # Ex: "acme-corp-dev-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version           # 1.31

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.environment == "prod" ? true : false
    endpoint_public_access  = var.environment == "prod" ? false : true
    public_access_cidrs     = var.environment == "prod" ? [] : ["0.0.0.0/0"]
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = var.environment == "prod" ? [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ] : ["api"]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }
}
```

#### Configuração por Ambiente

| Config | Dev/Staging | Prod |
|--------|:-----------:|:----:|
| **Endpoint público** |  (`0.0.0.0/0`) |  |
| **Endpoint privado** |  |  |
| **Logs habilitados** | `api` (1 tipo) | 5 tipos (full) |
| **Retenção de logs** | 7 dias | 90 dias |

**Por que endpoint privado em prod?**
- Reduz superfície de ataque — API server só acessível de dentro da VPC
- Compliance: SOC2/HIPAA exigem acesso controlado ao control plane
- Em dev/staging, público facilita o desenvolvimento local com `kubectl`

#### KMS Key para Secrets

```hcl
resource "aws_kms_key" "eks" {
  description         = "EKS Secret Encryption Key - ${local.name_prefix}"
  enable_key_rotation = true     # ← Rotação automática anual
}
```

**O que é criptografado?**
- Kubernetes Secrets armazenados no etcd
- Sem KMS, os secrets ficam em plaintext no etcd
- Com KMS, são criptografados em repouso (at rest)

#### Security Group do Cluster

```hcl
resource "aws_security_group" "cluster" {
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # Tudo
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Por que só egress?** O EKS managed automaticamente adiciona regras de ingress entre o control plane e os nodes. Definir aqui é apenas uma boa prática para controlar o egress.

---

### 2. `iam.tf` — 3 IAM Roles com Mínimo Privilégio

####  Role do Cluster (`eks-cluster-role`)

```
eks.amazonaws.com → AssumeRole → Policies:
├── AmazonEKSClusterPolicy        ← Gerenciar o cluster
└── AmazonEKSVPCResourceController ← Gerenciar ENIs para pods
```

####  Role dos Nodes (`eks-node-role`)

```
ec2.amazonaws.com → AssumeRole → Policies:
├── AmazonEKSWorkerNodePolicy      ← Registrar node no cluster
├── AmazonEKS_CNI_Policy           ← Gerenciar rede (VPC CNI)
├── AmazonEC2ContainerRegistryReadOnly ← Pull de imagens ECR
└── AmazonSSMManagedInstanceCore    ← Acesso via Session Manager (sem SSH)
```

####  Role do Karpenter (`karpenter-role`) — Condicional

```
ec2.amazonaws.com → AssumeRole → Policies:
├── AmazonEKSWorkerNodePolicy      ← Registrar nodes
├── AmazonEKS_CNI_Policy           ← Rede
├── AmazonEC2ContainerRegistryReadOnly ← ECR
├── AmazonSSMManagedInstanceCore    ← SSM
└── Custom Policy:                  ← Específica do Karpenter
    ├── ec2:CreateLaunchTemplate
    ├── ec2:CreateFleet
    ├── ec2:RunInstances
    ├── ec2:CreateTags
    ├── ec2:TerminateInstances
    ├── ec2:Describe*
    ├── pricing:GetProducts
    └── iam:PassRole
```

**Por que SSM em vez de SSH?**
- Não precisa abrir porta 22
- Não precisa gerenciar chaves SSH
- Auditoria nativa via CloudTrail
- Acesso via console AWS ou `aws ssm start-session`

---

### 3. `node-group.tf` — Node Group Principal

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-ondemand"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types    # ["m6i.large", "m6a.large"]
  disk_size       = var.node_disk_size          # 50 GB

  scaling_config {
    desired_size = var.node_desired_size    # 2
    min_size     = var.node_min_size        # 1
    max_size     = var.node_max_size        # 6
  }

  labels = {
    "node-pool" = "ondemand"
    "critical"  = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"         = "true"
  }
}
```

**Por que On-Demand + labels?**
- Workloads críticas (ArgoCD, controllers) rodam no node group On-Demand
- Workloads tolerantes a interrupção vão pro Karpenter (Spot)
- Labels permitem `nodeSelector` ou `nodeAffinity` nos pods

**Em dev:** `min_size=1, max_size=2` para não gastar com nós ociosos.

---

### 4. `karpenter.tf` — Escalonamento Inteligente

> ️ **IMPORTANTE:** O controller do Karpenter precisa ser instalado **SEPARADAMENTE** via Helm chart. Estes manifests apenas **configuram** o controller.

#### EC2NodeClass — Define o "tipo" de máquina

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: acme-corp-dev
spec:
  amiFamily: AL2                        # Amazon Linux 2
  role: acme-corp-dev-karpenter-role    # IAM Role
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: acme-corp-dev    # ← Descobre subnets pela tag
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: acme-corp-dev
```

#### NodePool — Regras de escalonamento

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: ["m6i", "m6a", "m7i", "c6i", "c7i", "r6i"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]       # ← Prioriza Spot
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
  limits:
    cpu: 2          # Dev: máx 2 vCPU (evita gastos surpresa)
                    # Prod: máx 100 vCPU
  disruption:
    consolidationPolicy: WhenUnderutilized    # ← Remove nós ociosos
    expireAfter: 720h                          # ← Recicla a cada 30 dias
```

#### Subnet Tags para Descoberta

```hcl
resource "aws_ec2_tag" "karpenter_subnets" {
  for_each    = toset(var.private_subnet_ids)
  resource_id = each.key
  key         = "karpenter.sh/discovery"
  value       = local.name_prefix
}
```

**Como o Karpenter funciona:**

```
Pod Pending (sem capacity)
        │
        ▼
Karpenter detecta
        │
        ▼
Avalia requirements (família, arch, capacity-type)
        │
        ▼
Escolhe instância mais barata (Spot se possível)
        │
        ▼
Cria node → Pod scheduled → 

... 10 min sem uso ...
        │
        ▼
Consolidation: remove nó ocioso → 
```

---

### 5. `wait-for-cluster.tf` — "Gambi Necessária"

> *"GAMBI? Sim. Mas necessária."*

**O problema:** O Terraform cria o cluster EKS e **imediatamente** tenta aplicar os manifests do Karpenter/ArgoCD. Mas o cluster ainda não está operacional.

**A solução:**

```hcl
resource "null_resource" "wait_for_cluster" {
  depends_on = [aws_eks_cluster.this]

  provisioner "local-exec" {
    command = <<EOF
      # 1. Aguarda cluster ACTIVE
      aws eks wait cluster-active --name ${cluster_name} --region ${region}

      # 2. Atualiza kubeconfig local
      aws eks update-kubeconfig --name ${cluster_name} --region ${region}

      # 3. Aguarda nodes READY (até 5 minutos)
      for i in $(seq 1 30); do
        READY_NODES=$(kubectl get nodes --no-headers | grep -c "Ready")
        if [ "$READY_NODES" -ge 1 ]; then
          echo " $READY_NODES node(s) Ready!"
          break
        fi
        sleep 10
      done
    EOF
  }
}

# Token de autenticação SÓ fica disponível DEPOIS do wait
data "aws_eks_cluster_auth" "this" {
  name       = aws_eks_cluster.this.name
  depends_on = [null_resource.wait_for_cluster]
}
```

**Fluxo temporal:**

```
0 min  ─── aws_eks_cluster.this criado (Terraform envia API call)
           Status: CREATING
5 min  ─── Control plane sendo provisionado
10 min ─── Status: ACTIVE
           wait_for_cluster: " Cluster EKS ACTIVE!"
12 min ─── Node group provisionando EC2
15 min ─── wait_for_cluster: " 2 node(s) Ready!"
           → Agora sim, aplica Karpenter + ArgoCD
```

---

### 6. `outputs.tf` — Valores Exportados

```hcl
output "cluster_id"                      # ID do cluster
output "cluster_name"                    # Nome (ex: acme-corp-dev-eks)
output "cluster_endpoint"               # URL da API (https://...)
output "cluster_security_group_id"      # SG do control plane
output "cluster_certificate_authority_data"  # CA cert (base64)
output "cluster_arn"                     # ARN completo
output "karpenter_role_arn"             # ARN da role do Karpenter (vazio se desabilitado)
output "node_role_arn"                  # ARN da role dos nodes
output "kms_key_arn"                    # ARN da KMS Key
```

Esses outputs são usados pelo módulo `tenant-argocd` para configurar os providers Helm/Kubectl.

---

##  Diagrama de Componentes

```
┌──────────────────────────────────── EKS Cluster ──────────────────────────────────┐
│                                                                                    │
│   ┌─── Control Plane (Gerenciado pela AWS) ─────────────────────────────────────┐ │
│   │  API Server ← endpoint (público em dev, privado em prod)                     │ │
│   │  etcd ← criptografado com KMS Key                                           │ │
│   │  Logs → CloudWatch (7d dev / 90d prod)                                       │ │
│   └──────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                    │
│   ┌─── Node Group: On-Demand ──────────────┐  ┌─── Karpenter Nodes ────────────┐ │
│   │  Instâncias: m6i.large / m6a.large     │  │  Instâncias: m6i/m6a/m7i/c6i  │ │
│   │  Labels: node-pool=ondemand            │  │  Capacity: Spot + On-Demand    │ │
│   │  Labels: critical=true                 │  │  CPU Limit: 2 (dev) / 100 (prod)│ │
│   │  Scaling: min=1, desired=2, max=6      │  │  Consolidation: auto           │ │
│   │  Disco: 50 GB                          │  │  Expiry: 30 dias               │ │
│   │  IAM: eks-node-role + SSM              │  │  IAM: karpenter-role           │ │
│   │                                         │  │                                │ │
│   │  [ArgoCD] [Controllers] [Criticals]    │  │  [Tenant Apps] [Spot Workloads]│ │
│   └─────────────────────────────────────────┘  └────────────────────────────────┘ │
│                                                                                    │
│   ┌─── IAM Roles ──────────────────────────────────────────────────────────────┐  │
│   │   Cluster Role → EKSClusterPolicy + VPCResourceController               │  │
│   │   Node Role    → WorkerNode + CNI + ECR + SSM                            │  │
│   │   Karpenter    → Node policies + Custom (EC2 Create/Terminate)           │  │
│   └────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                    │
│   ┌─── Segurança ──────────────────────────────────────────────────────────────┐  │
│   │   KMS Key (rotação automática) → Secrets encryption                      │  │
│   │  ️ Security Group → Egress only (AWS gerencia ingress)                    │  │
│   └────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

---

##  Exemplo de Uso

```hcl
module "tenant_eks" {
  source = "../../modules/tenant-eks"

  tenant             = "acme-corp"
  environment        = "dev"
  vpc_id             = module.tenant_network.vpc_id
  private_subnet_ids = module.tenant_network.private_subnet_ids
  enable_karpenter   = true

  # Defaults inteligentes para dev:
  # kubernetes_version = "1.31"
  # node_instance_types = ["m6i.large", "m6a.large"]
  # node_desired_size = 2
  # node_min_size = 1
  # node_max_size = 6
  
  tags = {
    CostCenter = "engineering"
  }
}
```

---

## ️ Troubleshooting

| Erro | Causa | Solução |
|------|-------|---------|
| `Error: waiting for EKS Cluster` | Cluster demora 10-15 min | Aguarde e rode `terraform apply` novamente |
| `no matches for kind EC2NodeClass` | Controller do Karpenter não instalado | Instale o Helm chart do Karpenter primeiro |
| `Unauthorized` | Token expirado ou kubeconfig inválido | `aws eks update-kubeconfig --name <cluster>` |
| `Error locking state` | Outro apply está rodando | `terraform force-unlock <ID>` |
| Nodes `NotReady` | Nodes ainda provisionando | Aguarde 2-3 min após cluster ACTIVE |

---

##  Conceitos para Estudar

| Conceito | O que é | Relevância |
|---------|---------|-----------|
| **EKS** | Elastic Kubernetes Service — K8s gerenciado pela AWS | Cluster management |
| **Control Plane** | Masters do K8s (API server, etcd, scheduler) | Gerenciado pela AWS |
| **Node Group** | Grupo de EC2s que rodam pods | Worker nodes |
| **Karpenter** | Auto-scaler de nova geração da AWS | Substitui cluster-autoscaler |
| **Spot Instances** | EC2s com desconto de 60-90% (podem ser interrompidas) | FinOps |
| **KMS** | Key Management Service — criptografia de secrets | Segurança |
| **IAM Roles** | Identidades AWS com permissões | Mínimo privilégio |
| **IRSA** | IAM Roles for Service Accounts | Identidade de pods |
| **null_resource** | Recurso Terraform sem estado real | Executar scripts |
| **provisioner "local-exec"** | Executa comando local durante apply | Workarounds |

---

[← Voltar ao README principal](../../../README.md)
