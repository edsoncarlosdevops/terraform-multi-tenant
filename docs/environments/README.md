#  Environments — Dev, Staging e Prod

[<- Voltar ao README principal](../../README.md)

---

##  Visão Geral

Os environments são as **instanciações concretas** dos módulos. Cada environment chama os módulos reutilizáveis (`tenant-network`, `tenant-eks`, `tenant-argocd`) com parâmetros específicos para o ambiente.

```
environments/
 dev/            <- Custo mínimo, desenvolvimento rápido
 staging/        <- Balanceado, validação antes de prod
 prod/           <- Alta disponibilidade, segurança máxima
```

---

##  Comparativo Completo

| Característica | Dev | Staging | Prod |
|:--------------|:---:|:-------:|:----:|
| **Tenant** | `acme-corp` | `acme-corp` | `acme-corp` |
| **CIDR** | `10.10.0.0/16` | `10.20.0.0/16` | `10.30.0.0/16` |
| **AZs** | 2 (`1a`, `1b`) | 3 (`1a`, `1b`, `1c`) | 3 (`1a`, `1b`, `1c`) |
| **Subnets Públicas** | 2 | 3 | 3 |
| **Subnets Privadas** | 2 | 3 | 3 |
| **NAT Gateway** |  Desabilitado |  1 (single) |  3 (1 por AZ) |
| **VPC Endpoints Gateway** |  S3 + DynamoDB |  S3 + DynamoDB |  S3 + DynamoDB |
| **VPC Endpoints Interface** |  |  |  ECR + Logs |
| **Flow Logs** |  |  |  (90 dias) |
| **EKS Cluster** |  |  (apenas network) |  (apenas network) |
| **Karpenter** |  (CPU limit: 2) | — | — |
| **ArgoCD** |  | — | — |
| **Backend S3 key** | `environments/dev/` | `environments/staging/` | `environments/prod/` |
| **CD Deploy** | Automático | Approval manual | Approval + freeze |
| **Custo estimado** | ~$75/mês | ~$40/mês (só rede) | ~$140/mês (só rede) |

> **Nota:** Staging e Prod atualmente só criam o módulo `tenant-network`. Os módulos EKS e ArgoCD podem ser adicionados seguindo o padrão do dev.

---

##  Ambiente: Dev

### Filosofia
> "Custo mínimo, iteração rápida. Sem NAT = $0 em rede."

### Arquivos

#### `environments/dev/main.tf`

O `main.tf` do dev é o mais completo — orquestra os 3 módulos:

```hcl
# 
# ORDEM DE EXECUÇÃO RECOMENDADA:
#   Apply #1: terraform apply -target=module.tenant_network \
#                              -target=module.tenant_eks
#   ⏳ Aguarda ~15 min o cluster EKS ficar ACTIVE
#   Apply #2: terraform apply (instala Karpenter + ArgoCD)
# 

terraform {
  backend "s3" {
    bucket         = "tfstate-saas-multi-tenant"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-lock"
  }
}

# Provider kubectl — SÓ funciona DEPOIS do cluster EKS ativo
provider "kubectl" {
  host                   = module.tenant_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

# Cadeia de dependências:
# tenant_network -> tenant_eks -> tenant_argocd
module "tenant_network" { ... }
module "tenant_eks"     { ... }     # Depende de network
module "tenant_argocd"  { ... }     # Depende de EKS
```

**Pontos-chave:**
1. **5 providers**: `aws`, `helm`, `kubernetes`, `kubectl` — todos necessários para EKS + ArgoCD
2. **Backend S3**: Key única `environments/dev/terraform.tfstate`
3. **Provider kubectl circular**: Configurado com outputs do módulo EKS (que ainda não existe no primeiro apply)
4. **Ordem explícita**: A documentação inline explica quando usar `-target`

#### `environments/dev/terraform.tfvars`

```hcl
tenant      = "acme-corp"
environment = "dev"

vpc = {
  cidr               = "10.10.0.0/16"
  azs                = ["us-east-1a", "us-east-1b"]
  public_subnets     = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnets    = ["10.10.10.0/24", "10.10.11.0/24"]
  enable_nat_gateway = false    # <- SEM NAT: custo zero de rede
  single_nat_gateway = true
}

tags = {
  CostCenter = "engineering"
  Project    = "saas-multi-tenant"
  Terraform  = "true"
  ManagedBy  = "github-actions"
}
```

#### `environments/dev/variables.tf`

7 variáveis: `tenant`, `environment`, `vpc`, `tags`, `infra_version`, `enable_karpenter`, `argocd_domain`

#### `environments/dev/outputs.tf`

10 outputs: `vpc_id`, `public/private_subnet_ids`, `nat_gateway_ids`, `eks_cluster_name/endpoint/arn`, `karpenter_role_arn`, `argocd_namespace/server`

---

##  Ambiente: Staging

### Filosofia
> "Balanceado: 1 NAT para acesso internet das subnets privadas. Validação antes de prod."

### Arquivos

#### `environments/staging/main.tf`

Atualmente **apenas o módulo network**:

```hcl
terraform {
  backend "s3" {
    key = "environments/staging/terraform.tfstate"
  }
}

module "tenant_network" {
  source      = "../../modules/tenant-network"
  tenant      = var.tenant
  environment = var.environment
  vpc         = var.vpc
  tags        = var.tags
}
```

#### `environments/staging/terraform.tfvars`

```hcl
tenant      = "acme-corp"
environment = "staging"

vpc = {
  cidr               = "10.20.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]    # <- 3 AZs
  public_subnets     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  private_subnets    = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true     # <- Apenas 1 NAT (economia)
}

tags = {
  CostCenter  = "engineering"
  Project     = "saas-multi-tenant"
  Environment = "staging"
  Terraform   = "true"
}
```

---

##  Ambiente: Prod

### Filosofia
> "Alta disponibilidade total. NAT por AZ, flow logs, endpoints Interface. Sem compromissos."

### Arquivos

#### `environments/prod/main.tf`

Atualmente **apenas o módulo network** (mesmo padrão do staging):

```hcl
terraform {
  backend "s3" {
    key = "environments/prod/terraform.tfstate"
  }
}

module "tenant_network" {
  source      = "../../modules/tenant-network"
  tenant      = var.tenant
  environment = var.environment
  vpc         = var.vpc
  tags        = var.tags
}
```

#### `environments/prod/terraform.tfvars`

```hcl
tenant      = "acme-corp"
environment = "prod"

vpc = {
  cidr               = "10.30.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets     = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
  private_subnets    = ["10.30.10.0/24", "10.30.11.0/24", "10.30.12.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = false    # <- NAT por AZ para HA
}
```

#### Output Extra: `vpc_flow_log_group`

O `outputs.tf` de prod expõe o `vpc_flow_log_group` (que não existe nos outros ambientes):

```hcl
output "vpc_flow_log_group" {
  value = try(module.tenant_network.vpc_flow_log_group, "")
}
```

---

##  Mapa de CIDRs

```
                    10.0.0.0/8 (Espaço privado)
                         
    
                                            
10.10.0.0/16         10.20.0.0/16        10.30.0.0/16
    DEV                STAGING              PROD
                                            
                  
Public            Public             Public    
.1.0              .1.0               .1.0      
.2.0              .2.0               .2.0      
                  .3.0               .3.0      
                  
Private           Private            Private   
.10.0             .10.0              .10.0     
.11.0             .11.0              .11.0     
                  .12.0              .12.0     
                  
```

**Por que CIDRs separados?**
- Permite **VPC Peering** entre ambientes se necessário
- Sem overlap de IPs
- Facilita identificação visual: `10.10.x = dev`, `10.20.x = staging`, `10.30.x = prod`

---

##  Como Expandir Staging/Prod

Para adicionar EKS + ArgoCD em staging/prod, siga o padrão do dev:

```hcl
# environments/staging/main.tf — adicione:

# 1. Providers adicionais
required_providers {
  helm       = { source = "hashicorp/helm", version = "~> 2.17" }
  kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
  kubectl    = { source = "gavinbunney/kubectl", version = "~> 1.14" }
}

# 2. Provider kubectl
provider "kubectl" {
  host                   = module.tenant_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.tenant_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.tenant_eks.cluster_name
}

# 3. Módulos EKS e ArgoCD
module "tenant_eks" {
  source             = "../../modules/tenant-eks"
  tenant             = var.tenant
  environment        = var.environment
  vpc_id             = module.tenant_network.vpc_id
  private_subnet_ids = module.tenant_network.private_subnet_ids
  tags               = var.tags
}

module "tenant_argocd" {
  source                             = "../../modules/tenant-argocd"
  tenant                             = var.tenant
  environment                        = var.environment
  cluster_endpoint                   = module.tenant_eks.cluster_endpoint
  cluster_certificate_authority_data = module.tenant_eks.cluster_certificate_authority_data
  cluster_name                       = module.tenant_eks.cluster_name
  tags                               = var.tags
}
```

---

##  Conceitos para Estudar

| Conceito | O que é | Relevância |
|---------|---------|-----------|
| **terraform.tfvars** | Arquivo de valores padrão para variáveis | Configuração por ambiente |
| **Backend S3** | Armazenamento remoto do state | State management |
| **`-target`** | Aplicar apenas recursos específicos | Deploy em fases |
| **Provider configuration** | Configurar providers com outputs de módulos | Dependência circular |
| **`depends_on` em módulos** | Forçar ordem de execução entre módulos | Orquestração |
| **VPC Peering** | Conectar VPCs de ambientes diferentes | Comunicação cross-env |
| **Environments no GitHub** | Protection rules para deploys | Approval gates |

---

[<- Voltar ao README principal](../../README.md)
