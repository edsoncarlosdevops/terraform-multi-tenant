# 🏛️ Decisões de Arquitetura

[← Voltar ao README principal](../../README.md)

---

## 📋 Visão Geral

Este documento explica as **decisões de design** por trás do projeto. Cada decisão inclui: o problema, as alternativas avaliadas, a escolha feita e a justificativa.

---

## 1. Modelo Multi-Tenant: Silo (VPC Dedicada)

### Problema

Como isolar tenants em uma plataforma SaaS na AWS?

### Alternativas

| Modelo | Descrição | Isolamento | Custo | Complexidade |
|--------|-----------|:----------:|:-----:|:------------:|
| **Pool** | Todos os tenants na mesma VPC, separados por namespace | 🟡 Baixo | 💚 Mínimo | 🟡 Médio |
| **Bridge** | VPC compartilhada com subnets separadas por tenant | 🟡 Médio | 🟡 Médio | 🟡 Médio |
| **Silo** | VPC dedicada por tenant | 🟢 Total | 🔴 Alto | 🟢 Simples |

### Escolha: **Silo**

### Justificativa

- **Isolamento total de rede**: Nenhum tráfego entre tenants é possível (nem por acidente)
- **Sem noisy neighbor**: Um tenant não afeta a performance de outro
- **Auditoria independente**: Flow logs, VPC endpoints e IAM por tenant
- **Onboarding/Offboarding**: Adicionar ou remover tenant = criar ou destruir módulo
- **Compliance**: SOC2/HIPAA/PCI-DSS exigem isolamento forte

### Trade-offs

- ❌ Custo mais alto (cada VPC tem seus NATs, endpoints, etc)
- ❌ Mais recursos para gerenciar
- ✅ Mitigado pela otimização por ambiente (dev sem NAT = $0)

---

## 2. Estrutura de Arquivos: Um Arquivo por Responsabilidade

### Problema

Como organizar arquivos Terraform sem que o `main.tf` fique com 500+ linhas?

### Alternativas

| Abordagem | Descrição |
|-----------|-----------|
| **Monolítico** | Tudo em `main.tf` |
| **Por recurso** | Um arquivo por tipo de recurso (`vpc.tf`, `subnet.tf`, `igw.tf`) |
| **Por responsabilidade** | Um arquivo por área de responsabilidade (`routing.tf`, `endpoints.tf`) |

### Escolha: **Por Responsabilidade**

### Resultado

```
modules/tenant-network/
├── main.tf           # VPC + IGW (36 linhas)
├── subnets.tf        # Subnets pub + priv (33 linhas)
├── nat-gateway.tf    # EIP + NAT (29 linhas)
├── routing.tf        # Route tables + associações (53 linhas)
├── endpoints.tf      # VPC Endpoints (105 linhas)
├── flow-logs.tf      # Flow Logs + IAM (80 linhas)
├── variables.tf      # 4 variáveis (29 linhas)
└── outputs.tf        # 8 outputs (33 linhas)
```

### Justificativa

- **Máximo ~105 linhas por arquivo** → Facilita code review
- **Nome do arquivo = responsabilidade** → Sabe onde procurar
- **Minimiza conflitos em Git** → Times paralelos editam arquivos diferentes
- **Facilita onboarding** → Novo dev entende a estrutura imediatamente

---

## 3. Variáveis: Contrato Enxuto com `object`

### Problema

Quantas variáveis um módulo deve receber? Como evitar "variable explosion"?

### Alternativas

| Abordagem | Variáveis | Exemplo |
|-----------|:---------:|---------|
| **Flat** | ~15 | `var.cidr`, `var.azs`, `var.public_subnets`, `var.enable_nat`... |
| **Object** | ~4 | `var.vpc.cidr`, `var.vpc.azs`, `var.vpc.enable_nat_gateway`... |

### Escolha: **Object com Optional**

```hcl
variable "vpc" {
  type = object({
    cidr               = string
    azs                = list(string)
    public_subnets     = list(string)
    private_subnets    = list(string)
    enable_nat_gateway = optional(bool, true)    # ← Default inteligente
    single_nat_gateway = optional(bool, true)
  })
}
```

### Justificativa

- **4 variáveis no módulo network** (vs 15+ no modelo flat)
- **Agrupamento semântico** → Todas as configs de VPC ficam juntas
- **Defaults inteligentes** → `optional(bool, true)` = funciona sem configurar
- **Tipagem forte** → Erro em tempo de `plan`, não de `apply`
- **Autocomplete** → IDEs mostram os campos do object

---

## 4. NAT Gateway Condicional

### Problema

O NAT Gateway custa ~$32/mês fixo + $0.045/GB de tráfego. Em dev, isso é desnecessário.

### Decisão

```hcl
count = var.vpc.enable_nat_gateway ? (
  var.vpc.single_nat_gateway ? 1 : length(local.azs)
) : 0
```

| Ambiente | NAT | Custo estimado |
|---------|:---:|:--------------:|
| Dev | ❌ (0 NATs) | $0/mês |
| Staging | ✅ (1 NAT) | ~$32/mês |
| Prod | ✅ (3 NATs) | ~$96/mês |

### Impacto em Dev

Sem NAT, recursos em subnets privadas **não acessam a internet**. Consequências:
- ❌ Pods não podem puxar imagens de registries públicos
- ❌ Nodes não podem baixar atualizações
- ✅ VPC Endpoints Gateway (S3, DynamoDB) continuam funcionando
- ✅ Para testes básicos com EKS, funciona

### Quando habilitar NAT em dev?

Se os pods precisarem acessar APIs externas ou puxar imagens do Docker Hub, mude `enable_nat_gateway = true` no `terraform.tfvars`.

---

## 5. VPC Endpoints: Gateway Grátis vs Interface Pago

### Problema

VPC Endpoints Interface custam ~$7-20/mês cada. Em dev/staging, não se justifica.

### Decisão

| Endpoint | Tipo | Dev | Staging | Prod | Custo |
|---------|------|:---:|:-------:|:----:|:-----:|
| S3 | Gateway | ✅ | ✅ | ✅ | $0 |
| DynamoDB | Gateway | ✅ | ✅ | ✅ | $0 |
| ECR API | Interface | ❌ | ❌ | ✅ | ~$7/mês |
| ECR Docker | Interface | ❌ | ❌ | ✅ | ~$7/mês |
| CloudWatch Logs | Interface | ❌ | ❌ | ✅ | ~$7/mês |

### Justificativa

- **Gateway Endpoints são GRÁTIS** → Sempre habilitados
- **Interface Endpoints são pagos** → Só em prod onde segurança e performance são críticas
- Em prod, ECR endpoints evitam que pull de imagens passe pelo NAT (economia de $0.045/GB)
- Em prod, Logs endpoint garante que logs cheguem mesmo sem internet

---

## 6. Karpenter vs Cluster Autoscaler

### Problema

Como escalar nodes automaticamente no EKS?

### Alternativas

| Ferramenta | Abordagem | Speed | Custo |
|-----------|-----------|:-----:|:-----:|
| **Cluster Autoscaler** | Reage a pods pending, adiciona nodes do ASG | 🟡 ~2-5 min | 🟡 |
| **Karpenter** | Avalia workloads, provisiona instâncias otimizadas | 🟢 ~30s-1 min | 🟢 |

### Escolha: **Karpenter**

### Justificativa

- **30s vs 3min** → Karpenter provisiona nodes 3-5x mais rápido
- **Spot + On-Demand** → Mix automático para otimizar custo
- **Consolidation** → Remove nós subutilizados automaticamente
- **Instance diversity** → Escolhe entre 6 famílias de instância
- **CPU Limit** → Controla gasto máximo (2 vCPU em dev, 100 em prod)
- **Reciclagem** → Nodes são trocados a cada 30 dias (segurança)

### Backup

O ApplicationSet do ArgoCD também instala o `cluster-autoscaler` como fallback, caso o Karpenter falhe.

---

## 7. ArgoCD ApplicationSets: Git vs List Generator

### Problema

Como gerenciar deploy de aplicações de tenants e infraestrutura?

### Decisão

| ApplicationSet | Generator | Propósito |
|---------------|-----------|-----------|
| `tenant-apps` | **Git** (directories) | Detecta pastas em `tenants/*` |
| `infra-apps` | **List** (static) | Componentes de infra com versões fixas |

### Por que Git Generator para tenants?

```
# Onboarding de novo tenant:
# 1. Cria pasta tenants/novo-tenant/ no repo
# 2. Adiciona manifests K8s
# 3. Push → ArgoCD detecta automaticamente
# 4. Application criado → Deploy automático
```

**Zero configuração manual** para novos tenants!

### Por que List Generator para infra?

Componentes de infra precisam de **versões controladas** (não podem ser "latest"):

```yaml
- name: ingress-nginx
  version: 4.12.0    # ← Versão fixa, controlada
- name: cert-manager
  version: 1.17.0
```

Atualizar versão = editar a lista → PR → Review → Merge → Deploy.

---

## 8. AppProjects: Zero-Trust entre Tenants e Infra

### Problema

Como evitar que um tenant acesse ou modifique recursos de outro?

### Decisão

```
┌─── AppProject: infra ──────────────────┐
│ ✅ Repos: Helm charts oficiais          │
│ ✅ Namespaces: ingress, cert-mgr, etc. │
│ ✅ Cluster resources: todos             │
│ ❌ Acesso a repos de tenants            │
└─────────────────────────────────────────┘

┌─── AppProject: tenants ────────────────┐
│ ✅ Repo: github.com/${tenant}           │
│ ✅ Namespaces: * (qualquer)             │
│ ✅ Cluster resources: Namespace, Quota  │
│ ❌ CRDs, ClusterRoles, etc.             │
└─────────────────────────────────────────┘
```

### Justificativa

- **Mínimo privilégio** → Tenants não podem criar CRDs ou ClusterRoles
- **Isolamento de repos** → Cada projeto só acessa seus repos autorizados
- **ResourceQuota/LimitRange** → Tenants podem limitar seus próprios namespaces
- **Orphaned resources** → ArgoCD avisa sobre recursos órfãos

---

## 9. IAM: Mínimo Privilégio com 3 Roles

### Problema

Quantas IAM Roles o EKS precisa e com quais permissões?

### Decisão

| Role | Quem assume | Permissões |
|------|-----------|-----------|
| **Cluster** | `eks.amazonaws.com` | `EKSClusterPolicy` + `VPCResourceController` |
| **Node** | `ec2.amazonaws.com` | `WorkerNode` + `CNI` + `ECR` + `SSM` |
| **Karpenter** | `ec2.amazonaws.com` | Node policies + Custom EC2 (condicional) |

### Por que SSM em vez de SSH?

| SSH | SSM |
|:---:|:---:|
| Precisa abrir porta 22 | Nenhuma porta aberta |
| Gerenciar chaves `.pem` | Sem chaves |
| Security Group permissivo | Sem SG adicional |
| Sem auditoria nativa | CloudTrail nativo |

---

## 10. Wait-for-Cluster: "Gambi Necessária"

### Problema

O Terraform cria o cluster EKS e **imediatamente** tenta aplicar manifests (Karpenter, ArgoCD). Mas o cluster ainda não está operacional (~15 min).

### Alternativas

| Abordagem | Prós | Contras |
|-----------|------|---------|
| **Separar em 2 applies** | Simples | Manual, propenso a erro |
| **`depends_on` apenas** | Nativo | Não espera cluster ficar ACTIVE |
| **`null_resource` com wait** | Espera de verdade | "Gambi" (provisioner local-exec) |

### Escolha: **null_resource com local-exec**

```hcl
resource "null_resource" "wait_for_cluster" {
  provisioner "local-exec" {
    command = <<EOF
      aws eks wait cluster-active --name ${cluster}
      # Polling de nodes: até 5 minutos
    EOF
  }
}
```

### Justificativa

- Sem esse wait, o `terraform apply` **sempre falha** na primeira vez
- O `depends_on` nativo não sabe esperar status ACTIVE
- É uma "gambi documentada" — o comentário no código explica exatamente por que existe
- Alternativa nativa (Terraform wait condition) não existe para EKS

---

## 11. Versionamento: SemVer Automático no CI/CD

### Problema

Como rastrear qual versão da infraestrutura criou cada recurso?

### Decisão

```
Git tag (SemVer) → TF_VAR_infra_version → Labels/Annotations nos recursos
```

| Etapa | O que acontece |
|-------|---------------|
| Merge para main | CD calcula próxima versão (patch increment) |
| Git tag | `v1.2.4` criada e enviada |
| terraform apply | `TF_VAR_infra_version=v1.2.4` |
| Namespace ArgoCD | Label: `infra-version: v1.2.4` |

### Benefícios

- **Rastreabilidade**: "Qual versão criou este namespace?" → `kubectl get ns argocd -o yaml`
- **Rollback**: Se a v1.2.4 quebrou, volte para v1.2.3
- **Auditoria**: Tags no Git funcionam como release notes

---

## 12. FinOps: Custo como Variável de Arquitetura

### Filosofia

> "Custo não é otimização posterior. É decisão de arquitetura."

### Decisões de FinOps

| Decisão | Economia | Onde |
|---------|:--------:|------|
| NAT condicional | $0-96/mês | `nat-gateway.tf` |
| Gateway endpoints (grátis) | $0 | `endpoints.tf` |
| Interface endpoints só em prod | ~$21/mês | `endpoints.tf` |
| Flow logs só em prod | ~$5/mês | `flow-logs.tf` |
| Karpenter Spot instances | 60-90% | `karpenter.tf` |
| Karpenter consolidation | Variável | `karpenter.tf` |
| CPU limit em dev (2 vCPU) | Ilimitado | `karpenter.tf` |
| CloudWatch 7d em dev | Variável | `main.tf` EKS |
| EKS logs mínimos em dev | ~$5/mês | `main.tf` EKS |
| Tags de CostCenter | Visibilidade | Todos recursos |
| Infracost preview em PRs | Prevenção | `ci.yml` |

### Custo Estimado por Ambiente

| Componente | Dev | Staging | Prod |
|-----------|:---:|:-------:|:----:|
| VPC/Subnets | $0 | $0 | $0 |
| NAT Gateway | $0 | ~$32 | ~$96 |
| VPC Endpoints | $0 | $0 | ~$21 |
| Flow Logs | $0 | $0 | ~$5 |
| EKS Control Plane | ~$73 | ~$73 | ~$73 |
| Node Group (2x m6i.large) | ~$140 | ~$140 | ~$140 |
| KMS Key | ~$1 | ~$1 | ~$1 |
| CloudWatch Logs | ~$2 | ~$2 | ~$10 |
| **TOTAL** | **~$216** | **~$248** | **~$346** |

> **Nota:** Dev pode ser destruído quando não está em uso → $0.
> Staging sem EKS = ~$32/mês. Prod sem EKS = ~$122/mês.

---

## 🧠 Resumo: Como um DevOps Sênior Pensa

```
1. PENSE    → Desenhe a arquitetura no papel
2. DEFINA   → Variáveis primeiro (o contrato)
3. CONSTRUA → Mínimo viável, iterativamente
4. VALIDE   → terraform plan a cada passo
5. DOCUMENTE → Enquanto constrói, não depois
6. OTIMIZE  → Custo só quando a estrutura básica funciona
```

> *"Um DevOps Sênior não é quem sabe tudo de cabeça.
> É quem sabe as perguntas certas a fazer e como validar
> cada passo antes de prosseguir."*

---

[← Voltar ao README principal](../../README.md)
