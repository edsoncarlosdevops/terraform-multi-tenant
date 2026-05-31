#  Bootstrap — Backend Remoto (S3 + DynamoDB)

[← Voltar ao README principal](../../README.pt-br.md)

---

##  O que é o Bootstrap?

O Bootstrap é o **primeiro passo** da infraestrutura. Ele cria os recursos necessários para que o Terraform armazene seu **state remotamente** e garanta **locking** para evitar conflitos.

> ️ **Este módulo deve ser aplicado manualmente apenas UMA VEZ**, antes de qualquer outro deploy.

---

## ️ Recursos Criados

### 1. S3 Bucket — `tfstate-saas-multi-tenant`

O bucket armazena os arquivos `.tfstate` de todos os ambientes.

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "tfstate-saas-multi-tenant"
}
```

**Configurações de segurança aplicadas:**

| Configuração | Valor | Por quê? |
|:------------|:------|:---------|
| **Versionamento** | `Enabled` | Permite recuperar states anteriores em caso de corrupção |
| **Criptografia** | `AES256` (SSE-S3) | Protege o state em repouso (contém dados sensíveis como ARNs, IPs) |
| **Bloqueio de acesso público** | 4 flags ativadas | Garante que o bucket nunca será exposto publicamente |

#### Versionamento

```hcl
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

**Por que versionar?**
- Se alguém rodar `terraform destroy` acidentalmente, o state anterior ainda existe
- Permite auditar mudanças históricas no state
- Facilita rollback de estados corrompidos

#### Criptografia Server-Side

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

**Por que criptografar?**
- O `.tfstate` contém informações sensíveis (endpoints, ARNs, configurações)
- Requisito de compliance (SOC2, HIPAA, PCI-DSS)
- `AES256` é o mais simples e sem custo adicional (vs KMS que cobra por chamada)

#### Bloqueio de Acesso Público

```hcl
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true   # Bloqueia ACLs públicas novas
  block_public_policy     = true   # Bloqueia bucket policies que permitem público
  ignore_public_acls      = true   # Ignora ACLs públicas existentes
  restrict_public_buckets = true   # Restringe acesso público ao bucket
}
```

### 2. DynamoDB Table — `tfstate-lock`

A tabela implementa **state locking** para evitar que dois `terraform apply` rodem ao mesmo tempo.

```hcl
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

**Como funciona o locking:**

```
┌──────────────────────────────────────────────────────┐
│  terraform apply (Terminal A)                        │
│    1. Escreve LockID na DynamoDB                     │
│    2. Aplica mudanças                                │
│    3. Remove LockID ao terminar                      │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  terraform apply (Terminal B — enquanto A roda)      │
│    1. Tenta escrever LockID → CONFLITO!              │
│    2. Retorna erro: "Error locking state"            │
│    3. Nenhuma mudança é feita                        │
└──────────────────────────────────────────────────────┘
```

**Por que `PAY_PER_REQUEST`?**
- O lock é acessado apenas durante `plan` e `apply`
- Na maioria dos projetos, são poucas chamadas por dia
- Custo praticamente zero (~$0.001/mês)

---

##  Arquivos

### `bootstrap/provider.tf`

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

**Detalhe:** O bootstrap **não usa backend remoto** (chicken-and-egg problem). O state do bootstrap fica local no `.terraform/` ou pode ser importado depois.

### `bootstrap/main.tf`

Contém os 4 recursos descritos acima (bucket, versionamento, criptografia, bloqueio público, tabela DynamoDB).

---

##  Como Usar

### Primeira vez (setup)

```bash
cd bootstrap
terraform init
terraform apply -auto-approve
```

**Output esperado:**
```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

### Verificar recursos criados

```bash
# Verificar bucket
aws s3 ls | grep tfstate

# Verificar tabela
aws dynamodb describe-table --table-name tfstate-lock --query 'Table.TableStatus'
```

---

##  Como os Ambientes Usam o Backend

Cada ambiente referencia o backend criado pelo bootstrap:

```hcl
# environments/dev/main.tf
terraform {
  backend "s3" {
    bucket         = "tfstate-saas-multi-tenant"
    key            = "environments/dev/terraform.tfstate"    # ← path único por ambiente
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-lock"                          # ← locking
  }
}
```

**Estrutura dos states no S3:**

```
s3://tfstate-saas-multi-tenant/
├── environments/
│   ├── dev/terraform.tfstate
│   ├── staging/terraform.tfstate
│   └── prod/terraform.tfstate
```

---

## ️ Cuidados

| Cenário | O que acontece | Como resolver |
|---------|---------------|---------------|
| Deletar o bucket S3 | State de TODOS os ambientes é perdido | **Nunca delete**. Se precisar, importe o state primeiro |
| Deletar a tabela DynamoDB | Locking para de funcionar | Recrie a tabela com o mesmo nome e hash key |
| Lock preso (apply travou) | Nenhum apply funciona | `terraform force-unlock <LOCK_ID>` |
| Mudar nome do bucket | Ambientes perdem referência ao state | Atualize todos os `backend "s3"` + migre com `terraform init -migrate-state` |

---

##  Conceitos para Estudar

| Conceito | O que é | Link |
|---------|---------|------|
| **Terraform State** | Arquivo que mapeia recursos reais ↔ configuração | [docs](https://developer.hashicorp.com/terraform/language/state) |
| **Remote Backend** | Armazenar state fora da máquina local | [docs](https://developer.hashicorp.com/terraform/language/settings/backends/s3) |
| **State Locking** | Prevenir applies simultâneos | [docs](https://developer.hashicorp.com/terraform/language/state/locking) |
| **S3 Versionamento** | Manter histórico de objetos no S3 | [docs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html) |

---

[← Voltar ao README principal](../../README.pt-br.md)
