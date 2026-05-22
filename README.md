# 🏗️ Infraestrutura SaaS Multi-Tenant — AWS + Terraform

## 📁 Estrutura do Projeto

```
terraform-multi-tenant/
├── bootstrap/                         # Setup inicial do backend (S3 + DynamoDB)
│   ├── main.tf
│   └── provider.tf
├── modules/
│   └── tenant-network/                # Módulo de rede reutilizável
│       ├── main.tf                    # VPC + Internet Gateway
│       ├── subnets.tf                 # Subnets públicas e privadas
│       ├── nat-gateway.tf             # NAT Gateway + Elastic IP
│       ├── routing.tf                # Route tables + associações
│       ├── endpoints.tf              # VPC Endpoints (S3, DynamoDB, ECR, Logs)
│       ├── flow-logs.tf             # VPC Flow Logs (apenas prod)
│       ├── variables.tf             # 4 variáveis: tenant, environment, vpc, tags
│       └── outputs.tf
└── environments/
    ├── dev/
    │   ├── main.tf                   # Custo reduzido: sem NAT, sem flow logs
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars
    ├── staging/
    │   ├── main.tf                   # Balanceado: 1 NAT, endpoints básicos
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars
    └── prod/
        ├── main.tf                   # HA: NAT por AZ, flow logs, endpoints
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars
```

## 🚀 Como usar

### 1. Bootstrap (primeira vez)

```bash
cd bootstrap
terraform init
terraform apply -auto-approve
```

### 2. Deploy por ambiente

```bash
# Dev (mais barato — sem NAT, sem flow logs)
cd environments/dev
terraform init
terraform apply -auto-approve

# Staging (balanceado)
cd environments/staging
terraform init
terraform apply -auto-approve

# Prod (alta disponibilidade)
cd environments/prod
terraform init
terraform apply -auto-approve
```

### 3. Destruir

```bash
cd environments/dev && terraform destroy -auto-approve
```

---

## 🧠 Decisões de Arquitetura

### 🔹 Modelo Multi-Tenant (Silo)

Cada tenant + environment recebe uma **VPC dedicada**. Isso garante:
- **Isolamento total de rede** entre tenants
- **Sem ruído de vizinho** (noisy neighbor)
- **Auditoria e compliance** por tenant
- Facilidade para **onboarding/offboarding** de tenants

### 🔹 Separação por responsabilidade (`main.tf` pequeno)

O módulo `tenant-network` foi dividido em 7 arquivos para facilitar manutenção e leitura.

### 🔹 Otimização de custos por ambiente

| Característica | Dev | Staging | Prod |
|---------------|-----|---------|------|
| NAT Gateway | ❌ | ✅ (1) | ✅ (3 — 1/AZ) |
| VPC Endpoints | ❌ | S3 + DynamoDB | S3 + DynamoDB + ECR + Logs |
| Flow Logs | ❌ | ❌ | ✅ (90 dias) |
| AZs | 2 | 3 | 3 |

### 🔹 Tags Obrigatórias

As 4 variáveis (`tenant`, `environment`, `vpc`, `tags`) garantem rastreabilidade total dos recursos para **cost allocation** em multi-tenancy.

---

## 📊 Próximos Módulos (expansão)

Para tornar a infraestrutura SaaS completa, os próximos passos seriam:

1. **`modules/tenant-compute`** — ECS Fargate + ECR por tenant
2. **`modules/tenant-database`** — Aurora PostgreSQL / DynamoDB com tenant_id
3. **`modules/tenant-auth`** — Cognito User Pool + tenant claim no JWT
4. **`modules/tenant-monitoring`** — CloudWatch Dashboard por tenant
5. **`modules/control-plane`** — API Gateway + Lambda para onboarding
6. **`modules/tenant-billing`** — AWS Budgets + Cost Tags por tenant
