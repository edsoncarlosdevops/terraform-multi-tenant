#  Módulo `tenant-network` — VPC Multi-Tenant

[<- Voltar ao README principal](../../../README.md)

---

##  Visão Geral

O módulo `tenant-network` cria toda a **infraestrutura de rede** para um tenant. Cada chamada cria uma **VPC isolada** com subnets públicas/privadas, NAT Gateway condicional, VPC Endpoints e Flow Logs.

**Filosofia:** Um arquivo por responsabilidade. O `main.tf` tem apenas 36 linhas.

---

##  Arquivos do Módulo

```
modules/tenant-network/
 main.tf           <- VPC + Internet Gateway + locals
 variables.tf      <- 4 variáveis (contrato do módulo)
 subnets.tf        <- Subnets públicas e privadas
 nat-gateway.tf    <- Elastic IP + NAT Gateway condicional
 routing.tf        <- Route tables públicas/privadas + associações
 endpoints.tf      <- VPC Endpoints (Gateway: S3/DynamoDB + Interface: ECR/Logs)
 flow-logs.tf      <- VPC Flow Logs + IAM Role (apenas prod)
 outputs.tf        <- 8 outputs
```

---

##  Variáveis de Entrada (Contrato)

O módulo recebe apenas **4 variáveis** — um contrato enxuto e bem definido:

```hcl
variable "tenant" {
  description = "Nome do tenant (ex: acme-corp, globo-saude)"
  type        = string
}

variable "environment" {
  description = "Ambiente de deploy (dev, staging, prod)"
  type        = string
}

variable "vpc" {
  description = "Configuração da VPC"
  type = object({
    cidr               = string           # Ex: "10.10.0.0/16"
    azs                = list(string)     # Ex: ["us-east-1a", "us-east-1b"]
    public_subnets     = list(string)     # Ex: ["10.10.1.0/24", "10.10.2.0/24"]
    private_subnets    = list(string)     # Ex: ["10.10.10.0/24", "10.10.11.0/24"]
    enable_nat_gateway = optional(bool, true)   # false = $0 em dev
    single_nat_gateway = optional(bool, true)   # true = 1 NAT, false = 1 por AZ
  })
}

variable "tags" {
  description = "Tags para aplicar em todos os recursos"
  type        = map(string)
  default     = {}
}
```

###  Sobre o tipo `object`

O uso de `object` com `optional` é uma prática avançada do Terraform:
- **`optional(bool, true)`** -> Se não passar a variável, o default é `true`
- Permite validação em tempo de `plan` (tipagem forte)
- Evita variáveis avulsas — todas as configs de VPC ficam agrupadas

---

##  Detalhamento por Arquivo

### 1. `main.tf` — VPC + Internet Gateway

```hcl
# Data sources para informações da AWS
data "aws_availability_zones" "available" { state = "available" }
data "aws_region" "current" {}

locals {
  name_prefix = "${var.tenant}-${var.environment}"    # Ex: "acme-corp-dev"
  azs         = length(var.vpc.azs) > 0 ? var.vpc.azs : data.aws_availability_zones.available.names
}
```

**Conceitos importantes:**
- **`data.aws_availability_zones`**: Busca AZs disponíveis automaticamente. Se o usuário não especificar AZs, usa todas.
- **`name_prefix`**: Padrão de nomenclatura `{tenant}-{environment}` usado em TODOS os recursos
- **`enable_dns_hostnames = true`**: Necessário para VPC Endpoints Interface e resolução DNS privada

**VPC:**
- CIDR configurável por ambiente (ex: `10.10.0.0/16`, `10.20.0.0/16`, `10.30.0.0/16`)
- DNS habilitado (necessário para EKS e VPC Endpoints)
- Tags com tenant + environment para rastreabilidade

**Internet Gateway:**
- Permite que subnets públicas acessem a internet
- É pré-requisito para o NAT Gateway

---

### 2. `subnets.tf` — Subnets Públicas e Privadas

```hcl
resource "aws_subnet" "public" {
  count                   = length(var.vpc.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.vpc.public_subnets[count.index]
  availability_zone       = local.azs[count.index % length(local.azs)]
  map_public_ip_on_launch = true     # <- IP público automático
}

resource "aws_subnet" "private" {
  count             = length(var.vpc.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.vpc.private_subnets[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]
}
```

**Distribuição de AZs com operador `%`:**

```
# Com 3 subnets e 2 AZs:
# count.index=0 -> AZ[0 % 2] = AZ[0] = us-east-1a
# count.index=1 -> AZ[1 % 2] = AZ[1] = us-east-1b
# count.index=2 -> AZ[2 % 2] = AZ[0] = us-east-1a  (volta ao início)
```

**Tags importantes:**
- `Tier = "public"` ou `Tier = "private"` -> Usado para filtrar subnets no console AWS
- `Tenant` e `Environment` -> Rastreabilidade e cost allocation

---

### 3. `nat-gateway.tf` — NAT Gateway Condicional

O NAT Gateway é o recurso **mais caro** da rede (~$32/mês + $0.045/GB).

```hcl
# Elastic IP — sempre criado (necessário para o NAT)
resource "aws_eip" "nat" {
  count  = var.vpc.single_nat_gateway ? 1 : length(local.azs)
  domain = "vpc"
}

# NAT Gateway — condicional
resource "aws_nat_gateway" "this" {
  count = var.vpc.enable_nat_gateway ? (
    var.vpc.single_nat_gateway ? 1 : length(local.azs)
  ) : 0    # <- Se enable_nat_gateway=false, cria ZERO NATs
}
```

**Lógica do `count`:**

| `enable_nat_gateway` | `single_nat_gateway` | Resultado | Custo/mês |
|:--------------------:|:--------------------:|:---------:|:---------:|
| `false` | qualquer | **0 NATs** | $0 |
| `true` | `true` | **1 NAT** | ~$32 |
| `true` | `false` | **N NATs** (1 por AZ) | ~$96 (3 AZs) |

**`depends_on = [aws_internet_gateway.this]`** -> O NAT precisa do IGW para funcionar. Sem isso, o Terraform pode tentar criar o NAT antes do IGW.

---

### 4. `routing.tf` — Tabelas de Rotas

```hcl
# Route Table Pública — tráfego 0.0.0.0/0 vai pro IGW
resource "aws_route_table" "public" {
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

# Route Tables Privadas — tráfego 0.0.0.0/0 vai pro NAT (se existir)
resource "aws_route_table" "private" {
  count = var.vpc.single_nat_gateway ? 1 : length(local.azs)

  dynamic "route" {
    for_each = var.vpc.enable_nat_gateway ? [1] : []   # <- Rota condicional
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.vpc.single_nat_gateway ?
        aws_nat_gateway.this[0].id :
        aws_nat_gateway.this[count.index].id
    }
  }
}
```

**Bloco `dynamic "route"`:**
- Se `enable_nat_gateway = false` -> `for_each = []` -> **nenhuma rota é criada**
- Se `enable_nat_gateway = true` -> `for_each = [1]` -> **1 rota para o NAT**

**Associações:**
- Cada subnet pública é associada à route table pública
- Cada subnet privada é associada à route table privada correspondente (por AZ)

---

### 5. `endpoints.tf` — VPC Endpoints

VPC Endpoints permitem que recursos acessem serviços AWS **sem passar pela internet**.

#### Gateway Endpoints (GRÁTIS — todos os ambientes)

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.public.id]
  )
}

resource "aws_vpc_endpoint" "dynamodb" {
  # Mesmo padrão do S3
}
```

**Por que Gateway Endpoints?**
- **Custo ZERO** — não cobra por hora nem por GB
- S3 e DynamoDB são os serviços mais acessados (state, logs, cache)
- Reduz tráfego pelo NAT Gateway (economia adicional)

#### Interface Endpoints (APENAS PROD — ~$7-20/mês cada)

```hcl
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.environment == "prod" ? 1 : 0   # <- Só em prod

  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true
}
```

| Endpoint | Serviço | Por que em prod? |
|---------|---------|-----------------|
| `ecr.api` | ECR API | Pull de imagens Docker sem internet |
| `ecr.dkr` | ECR Docker | Pull de layers Docker sem internet |
| `logs` | CloudWatch Logs | Envio de logs sem internet |

**Security Group dos Endpoints:**
```hcl
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [var.vpc.cidr]   # <- Apenas tráfego de dentro da VPC
}
```

---

### 6. `flow-logs.tf` — VPC Flow Logs (APENAS PROD)

Captura metadados de todo tráfego de rede na VPC.

```hcl
resource "aws_flow_log" "this" {
  count = var.environment == "prod" ? 1 : 0

  traffic_type    = "ALL"        # ACCEPT + REJECT
  vpc_id          = aws_vpc.this.id
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
}
```

**O que é capturado (exemplo):**
```
2 123456789012 eni-abc123 10.10.1.5 52.94.76.7 443 49152 6 25 20000 ACCEPT
                                                           Aceito
                                                      Bytes
                                                    Pacotes
                                                   Protocolo (TCP)
                                              Porta destino
                                           Porta origem
                                 IP destino
                        IP origem
              ENI
  Account ID
 Versão
```

**IAM Role dedicada:**
- Usa **mínimo privilégio** — apenas permissões de CloudWatch Logs
- `assume_role_policy` -> Apenas o serviço `vpc-flow-logs.amazonaws.com` pode assumir

**CloudWatch Log Group:**
- Retenção: **90 dias** (custo-eficiente para compliance)

---

### 7. `outputs.tf` — Valores Exportados

```hcl
output "vpc_id"               { value = aws_vpc.this.id }
output "vpc_cidr"             { value = aws_vpc.this.cidr_block }
output "public_subnet_ids"    { value = aws_subnet.public[*].id }
output "private_subnet_ids"   { value = aws_subnet.private[*].id }
output "azs"                  { value = local.azs }
output "nat_gateway_ids"      { value = try(aws_nat_gateway.this[*].id, []) }
output "internet_gateway_id"  { value = aws_internet_gateway.this.id }
output "vpc_flow_log_group"   { value = try(aws_cloudwatch_log_group.flow_logs[0].name, "") }
```

**Nota:** O uso de `try()` garante que o output retorna um valor vazio (`[]` ou `""`) quando o recurso não existe (ex: NAT desabilitado em dev).

---

##  Diagrama de Rede

```
 VPC (10.x.0.0/16) 
                                                                                  
    AZ-a    AZ-b    AZ-c 
                                                                            
      Public       Public       Public  
      10.x.1.0/24            10.x.2.0/24            10.x.3.0/24 
      map_public_ip=yes       map_public_ip=yes                    
        NAT GW                                             
                              
                                                           
                                                                           
      Private       Private       Private  
      10.x.10.0/24           10.x.11.0/24           10.x.12.0/24 
      [EKS Nodes]            [EKS Nodes]            [EKS Nodes]  
                
       
                                                                                  
    VPC Endpoints 
    S3 (Gateway)  FREE    DynamoDB (Gateway)  FREE                         
    ECR (Interface)  PROD  Logs (Interface)  PROD                         
   
                                                                                  
    Internet Gateway       Flow Logs  
    Público -> Subnets pub          PROD ONLY -> CloudWatch (90 dias)      
         

```

---

##  Exemplo de Uso

```hcl
module "tenant_network" {
  source = "../../modules/tenant-network"

  tenant      = "acme-corp"
  environment = "dev"
  
  vpc = {
    cidr               = "10.10.0.0/16"
    azs                = ["us-east-1a", "us-east-1b"]
    public_subnets     = ["10.10.1.0/24", "10.10.2.0/24"]
    private_subnets    = ["10.10.10.0/24", "10.10.11.0/24"]
    enable_nat_gateway = false    # Dev: sem NAT = $0
    single_nat_gateway = true
  }
  
  tags = {
    CostCenter = "engineering"
    Project    = "saas-multi-tenant"
  }
}
```

---

##  Conceitos para Estudar

| Conceito | O que é | Relevância |
|---------|---------|-----------|
| **VPC** | Virtual Private Cloud — rede isolada na AWS | Base de toda infraestrutura |
| **CIDR** | Classless Inter-Domain Routing — range de IPs | Define tamanho da rede |
| **Subnets** | Subdivisões da VPC em AZs | Distribuição de carga |
| **NAT Gateway** | Permite acesso internet para subnets privadas | Recurso mais caro |
| **IGW** | Internet Gateway — porta de entrada para tráfego público | Necessário para público |
| **Route Tables** | Regras de roteamento de tráfego | Controle de fluxo |
| **VPC Endpoints** | Acesso direto a serviços AWS sem internet | Segurança + economia |
| **Flow Logs** | Captura metadata de tráfego de rede | Auditoria/compliance |
| **`count` vs `for_each`** | Criar N recursos dinamicamente | Padrão Terraform |
| **`dynamic` blocks** | Gerar blocos HCL condicionalmente | Rotas condicionais |

---

[<- Voltar ao README principal](../../../README.md)
