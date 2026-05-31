#  Scripts Utilitários

[← Voltar ao README principal](../../README.pt-br.md)

---

##  Visão Geral

O projeto inclui 2 scripts utilitários para auxiliar no setup inicial e no versionamento local:

```
scripts/
├── setup-github.sh   ← Prepara o repo para o primeiro push
└── version.sh        ← Versionamento SemVer local
```

---

##  Script 1: `setup-github.sh`

### Propósito

Prepara o repositório local para o primeiro push no GitHub. Automatiza verificações que deveriam ser feitas manualmente.

### Uso

```bash
./scripts/setup-github.sh
```

### O que faz (4 etapas)

```
┌─────────────────────────────────────────────────────────┐
│  [1/4] Verificando Git...                               │
│   Git OK                                              │
│  (ou ️ com instruções para criar o repo)               │
├─────────────────────────────────────────────────────────┤
│  [2/4] Formatando código Terraform...                   │
│  terraform fmt -recursive                               │
│   Formatação concluída                                │
├─────────────────────────────────────────────────────────┤
│  [3/4] Validando sintaxe (sem AWS)...                   │
│  terraform init -backend=false                          │
│  terraform validate                                     │
│   dev - OK                                            │
│   staging - OK                                        │
│   prod - OK                                           │
├─────────────────────────────────────────────────────────┤
│  [4/4] Resumo do que vai subir:                         │
│                                                          │
│   Estrutura:                                          │
│  ├── bootstrap/          (S3 + DynamoDB)                │
│  ├── modules/                                           │
│  │   ├── tenant-network/ (VPC + subnets + NAT)          │
│  │   ├── tenant-eks/     (Cluster + NodeGroup)          │
│  │   └── tenant-argocd/  (ArgoCD + AppSets)             │
│  ├── environments/                                      │
│  │   ├── dev/            (custo zero)                   │
│  │   ├── staging/        (balanceado)                   │
│  │   └── prod/           (HA)                           │
│  └── .github/workflows/  (pipelines)                    │
│                                                          │
│   Secrets necessários no GitHub:                      │
│     - AWS_ACCOUNT_ID                                    │
│     - SLACK_WEBHOOK (opcional)                          │
│     - INFRACOST_API_KEY (opcional)                      │
│                                                          │
│   IAM Role necessária na AWS:                        │
│     - github-actions-terraform                          │
│                                                          │
│  ════════════════════════════════════════                │
│  PRONTO PARA SUBIR!                                     │
│  ════════════════════════════════════════                │
│                                                          │
│  Comandos:                                              │
│    git add .                                            │
│    git commit -m 'feat: infra multi-tenant completa'    │
│    git push -u origin main                              │
└─────────────────────────────────────────────────────────┘
```

### Detalhes Técnicos

```bash
set -euo pipefail    # ← Aborta em qualquer erro
```

| Flag | Significado |
|------|-----------|
| `-e` | Exit on error — qualquer comando que falhar para o script |
| `-u` | Unset variables — usar variável não declarada é erro |
| `-o pipefail` | Pipe fail — se qualquer comando em um pipe falhar, todo o pipe falha |

**`terraform init -backend=false`** — Inicializa sem conectar ao S3 backend. Permite validar sintaxe sem credenciais AWS.

**`terraform validate`** — Verifica se a sintaxe está correta sem criar nenhum recurso.

---

## ️ Script 2: `version.sh`

### Propósito

Gerencia versionamento SemVer (Semantic Versioning) local. Permite ver, calcular e criar tags sem usar o CI/CD.

### Uso

```bash
# Ver versão atual
./scripts/version.sh current

# Ver próxima versão (sem criar)
./scripts/version.sh next

# Criar e enviar a tag
./scripts/version.sh tag

# Ajuda
./scripts/version.sh help
```

### Exemplos de Output

```bash
$ ./scripts/version.sh current
 Versão atual: v1.2.3
 Commit:       abc1234

$ ./scripts/version.sh next
 Última tag:  v1.2.3
 Próxima tag: v1.2.4

Para aplicar com essa versão:
  export TF_VAR_infra_version=v1.2.4
  terraform apply

$ ./scripts/version.sh tag
️ Criando tag v1.2.4...
 Tag v1.2.4 criada e enviada!
```

### Funções Internas

```bash
get_last_tag() {
  git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
}
```
- `git describe --tags --abbrev=0` → Retorna a tag anotada mais recente
- `2>/dev/null` → Suprime erro se não existir nenhuma tag
- `|| echo "v0.0.0"` → Fallback para v0.0.0 se não houver tags

```bash
get_next_version() {
  local LAST_TAG=$1
  local MAJOR=$(echo "$LAST_TAG" | cut -d. -f1 | tr -d 'v')
  local MINOR=$(echo "$LAST_TAG" | cut -d. -f2)
  local PATCH=$(echo "$LAST_TAG" | cut -d. -f3)
  echo "v$MAJOR.$MINOR.$((PATCH + 1))"
}
```

**Parsing da versão:**
```
v1.2.3
│ │ │ └── PATCH = 3  → cut -d. -f3
│ │ └──── MINOR = 2  → cut -d. -f2
│ └────── MAJOR = 1  → cut -d. -f1 | tr -d 'v' (remove o 'v')
└──────── Prefixo removido por tr -d
```

**Incremento:** Sempre incrementa o PATCH (`$((PATCH + 1))`). Para incrementar MINOR ou MAJOR, faça manualmente.

### SemVer Explicado

```
v MAJOR . MINOR . PATCH
  │       │       │
  │       │       └── Correção de bugs (backward compatible)
  │       └────────── Nova funcionalidade (backward compatible)
  └────────────────── Breaking change (incompatível)

Exemplos:
  v1.2.3 → v1.2.4  (fix: ajuste na route table)
  v1.2.4 → v1.3.0  (feat: novo módulo de database)
  v1.3.0 → v2.0.0  (BREAKING: mudança na interface do módulo)
```

### Integração com Terraform

O `infra_version` é usado para rastreabilidade:

```bash
# Via script
export TF_VAR_infra_version=$(./scripts/version.sh next | grep "Próxima tag" | awk '{print $NF}')
terraform apply

# Via CI/CD (automático)
# O cd.yml faz isso automaticamente:
env:
  TF_VAR_infra_version: ${{ needs.version.outputs.new_tag }}
```

Resultado nos recursos:
```yaml
# Namespace do ArgoCD terá:
metadata:
  labels:
    infra-version: "v1.2.4"     # ← De onde veio esse namespace?
  annotations:
    infra.tenant.io/version: "v1.2.4"
```

---

##  Conceitos para Estudar

| Conceito | O que é | Relevância |
|---------|---------|-----------|
| **SemVer** | Semantic Versioning (`MAJOR.MINOR.PATCH`) | Padrão de versionamento |
| **Git Tags** | Marcadores em commits | Releases |
| **`set -euo pipefail`** | Modo estrito de scripts bash | Robustez |
| **`terraform fmt`** | Formatação automática de HCL | Padronização |
| **`terraform validate`** | Validação de sintaxe | Quality gate |
| **`TF_VAR_*`** | Variáveis de ambiente do Terraform | Injeção de valores |
| **Anotated tags** | Tags com mensagem (`git tag -a`) | Releases com metadata |

---

[← Voltar ao README principal](../../README.pt-br.md)
