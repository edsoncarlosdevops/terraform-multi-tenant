# ️ CI/CD — GitHub Actions Workflows

[← Voltar ao README principal](../../README.md)

---

##  Visão Geral

O projeto usa **3 workflows** do GitHub Actions que cobrem todo o ciclo de vida:

```
PR criado → CI (qualidade + segurança + plan)
PR merged → CD (versionamento + apply + notificação)
Domingo   → Security Weekly (DAST no cluster)
```

---

##  Arquivos

```
.github/workflows/
├── ci.yml                 ← CI unificado: fmt + lint + SAST + plan
├── cd.yml                 ← CD unificado: tag + apply + Slack
└── security-weekly.yml    ← DAST semanal: kube-bench + Popeye + Kubescape
```

---

##  Workflow 1: CI (`ci.yml`)

### Trigger

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'
      - 'bootstrap/**'
```

**Só roda quando:** Arquivos de infra mudam em um PR para `main`.

### Permissões

```yaml
permissions:
  id-token: write        # OIDC para assumir role AWS
  contents: read         # Ler código
  pull-requests: write   # Comentar no PR
  security-events: write # Upload SARIF para GitHub Security
```

### Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                      Job: quality                               │
│                                                                  │
│  ┌──────────────────┐                                           │
│  │ 1. terraform fmt  │ ← Verifica formatação                    │
│  │    -check         │   continue-on-error: true                │
│  └────────┬─────────┘                                           │
│           │                                                      │
│  ┌────────▼─────────┐                                           │
│  │ 2. TFLint         │ ← Lint de best practices                │
│  │    --format compact│   continue-on-error: true               │
│  └────────┬─────────┘                                           │
│           │                                                      │
│  ┌────────▼──────────────┐                                      │
│  │ 3. Checkov (IaC)      │ ← Scan de misconfigurations          │
│  │    → checkov.sarif     │   Upload para GitHub Security        │
│  └────────┬──────────────┘                                      │
│           │                                                      │
│  ┌────────▼──────────────┐                                      │
│  │ 4. Trivy (filesystem) │ ← Vuln + misconfig + secrets         │
│  │    → trivy.sarif       │   Severity: HIGH, CRITICAL           │
│  └────────┬──────────────┘                                      │
│           │                                                      │
│  ┌────────▼──────────────┐                                      │
│  │ 5. Gitleaks (secrets) │ ← Scan de secrets no código/commits  │
│  └───────────────────────┘                                      │
└──────────────────────────────┬──────────────────────────────────┘
                                │ needs: quality
┌──────────────────────────────▼──────────────────────────────────┐
│                      Job: plan                                   │
│              Matrix: [dev, staging, prod]                        │
│              fail-fast: false                                    │
│                                                                  │
│  ┌──────────────────┐                                           │
│  │ terraform init    │ ← -backend=false (sem creds AWS)         │
│  │    -backend=false │                                          │
│  └────────┬─────────┘                                           │
│           │                                                      │
│  ┌────────▼─────────┐                                           │
│  │ terraform validate│ ← Validação de sintaxe                   │
│  └────────┬─────────┘                                           │
│           │                                                      │
│  ┌────────▼─────────┐                                           │
│  │ terraform plan    │ ← Plan sem aplicar                       │
│  │    -no-color      │   continue-on-error: true                │
│  └────────┬─────────┘                                           │
│           │                                                      │
│  ┌────────▼──────────────────────────────────────────────────┐  │
│  │ Comentário no PR:                                          │  │
│  │  ##  Plan - `dev`                                       │  │
│  │  <details><summary>Show Plan</summary>                     │  │
│  │  ```terraform                                              │  │
│  │  ... output do plan ...                                    │  │
│  │  ```                                                       │  │
│  │  </details>                                                │  │
│  │   Plan succeeded                                         │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Detalhes Técnicos

**`-backend=false` no CI:**
- O CI não tem credenciais AWS no job `quality` (são caras e desnecessárias)
- `terraform init -backend=false` inicializa sem conectar ao S3
- `terraform validate` funciona sem backend

**`continue-on-error: true`:**
- Nenhuma ferramenta de segurança **bloqueia** o PR
- São checks informativos para revisão humana
- Para bloquear, remova o `continue-on-error`

**Matrix strategy:**
```yaml
strategy:
  matrix:
    environment: [dev, staging, prod]
  fail-fast: false    # ← Roda TODOS mesmo se um falhar
```

---

##  Workflow 2: CD (`cd.yml`)

### Trigger

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'
      - 'bootstrap/**'
```

**Só roda quando:** Merge para `main` com mudanças em infra.

### Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│                      Job: version                                │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │ 1. Calcula SemVer                                         │   │
│  │    LAST_TAG = git describe --tags --abbrev=0              │   │
│  │    Se v0.0.0 → v0.1.0                                    │   │
│  │    Senão → v{major}.{minor}.{patch+1}                     │   │
│  │                                                           │   │
│  │ 2. Cria tag anotada                                       │   │
│  │    git tag -a v1.2.4 -m "Release v1.2.4"                 │   │
│  │    git push origin v1.2.4                                  │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                   │
│  Output: new_tag = "v1.2.4"                                      │
└──────────────────────┬───────────────────────────────────────────┘
                        │ needs: version
┌──────────────────────▼───────────────────────────────────────────┐
│                      Job: deploy                                  │
│              Matrix: [dev, staging, prod]                         │
│              environment: ${{ matrix.environment }}               │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │ 1. Detect Changes                                         │   │
│  │    git diff HEAD~1...HEAD | grep environments/dev/        │   │
│  │    → changed=true ou changed=false                        │   │
│  └────────┬──────────────────────────────────────────────────┘   │
│           │ if changed=true                                       │
│  ┌────────▼──────────────────────────────────────────────────┐   │
│  │ 2. Configure AWS (OIDC)                                    │   │
│  │    role-to-assume: github-actions-terraform                │   │
│  └────────┬──────────────────────────────────────────────────┘   │
│           │                                                       │
│  ┌────────▼──────────────────────────────────────────────────┐   │
│  │ 3. terraform init + apply -auto-approve                    │   │
│  │    TF_VAR_infra_version = v1.2.4  ← Da etapa version      │   │
│  └────────┬──────────────────────────────────────────────────┘   │
│           │                                                       │
│  ┌────────▼──────────────────────────────────────────────────┐   │
│  │ 4. Slack Notification                                      │   │
│  │     Deploy - `dev`                                       │   │
│  │    Versão: v1.2.4                                          │   │
│  │    Status: success                                         │   │
│  └───────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### Detalhes Técnicos

**Detect Changes:**
```bash
CHANGED=$(git diff --name-only HEAD~1...HEAD | grep "^environments/dev/" || echo "")
```
- Compara o último commit com o anterior
- Se nenhum arquivo do ambiente mudou, **pula o deploy** (economia de tempo e dinheiro)

**OIDC Authentication:**
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-terraform
```
- **Sem chaves de acesso!** Usa OIDC (OpenID Connect) para assumir uma IAM Role
- Mais seguro que access keys (sem segredo para vazar)
- Ver [docs/github-actions-setup.md](../github-actions-setup.md) para configuração

**`TF_VAR_infra_version`:**
```yaml
env:
  TF_VAR_infra_version: ${{ needs.version.outputs.new_tag }}
```
- A versão da tag é passada como variável de ambiente para o Terraform
- Aparece nos labels/annotations dos recursos (rastreabilidade)

**Environment protection rules:**

| Ambiente | Proteção | Comportamento |
|---------|----------|--------------|
| `dev` | Nenhuma | Deploy automático no merge |
| `staging` | Required reviewers | Precisa aprovação manual |
| `prod` | Required reviewers + Wait timer | Aprovação + 10 min de espera |

---

##  Workflow 3: Security Weekly (`security-weekly.yml`)

### Trigger

```yaml
on:
  schedule:
    - cron: '0 8 * * 0'    # Domingo às 8h UTC
  workflow_dispatch:         # Pode rodar manualmente
```

### Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                      Job: dast                                   │
│              environment: prod                                   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ 1. kube-bench (CIS Kubernetes Benchmark)                  │   │
│  │    - Roda pod efêmero no cluster                          │   │
│  │    - Verifica compliance com CIS benchmarks               │   │
│  │    - Output: JSON com passes/fails por seção              │   │
│  └────────┬─────────────────────────────────────────────────┘   │
│           │                                                      │
│  ┌────────▼─────────────────────────────────────────────────┐   │
│  │ 2. Popeye (Sanidade do Cluster)                           │   │
│  │    - Analisa recursos do cluster                          │   │
│  │    - Detecta: pods sem limits, images latest, etc.        │   │
│  │    - Output: HTML report                                   │   │
│  └────────┬─────────────────────────────────────────────────┘   │
│           │                                                      │
│  ┌────────▼─────────────────────────────────────────────────┐   │
│  │ 3. Kubescape (NSA/CISA Framework)                         │   │
│  │    - Verifica compliance com framework NSA/CISA            │   │
│  │    - Output: SARIF → GitHub Security tab                   │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### Ferramentas DAST

| Ferramenta | O que verifica | Formato |
|-----------|---------------|---------|
| **kube-bench** | CIS Benchmark (configurações do cluster) | JSON no Step Summary |
| **Popeye** | Recursos mal configurados (pods, services, etc) | HTML report |
| **Kubescape** | Framework NSA/CISA + MITRE ATT&CK | SARIF → GitHub Security |

**kube-bench exemplo de output:**
```
[PASS] 1.1.1 Ensure that the API server pod specification file permissions are set to 644
[FAIL] 1.1.2 Ensure that the API server pod specification file ownership is root:root
[WARN] 1.2.1 Ensure that the --anonymous-auth argument is set to false
```

---

##  Secrets Necessários

| Secret | Obrigatório | Onde configurar |
|--------|:-----------:|:---------------|
| `AWS_ACCOUNT_ID` |  | Settings → Secrets → Actions |
| `SLACK_WEBHOOK` |  | Settings → Secrets → Actions |
| `INFRACOST_API_KEY` |  | Settings → Secrets → Actions |

---

##  Fluxo Completo

```
     ┌────────────────────────────────────────────────────┐
     │              Developer Workflow                     │
     └────────────────────────────────────────────────────┘

     1. git checkout -b feature/add-tenant
     2. Edita modules/ ou environments/
     3. git push origin feature/add-tenant
     4. Abre PR para main
                │
                ▼
     ┌─────────────────────┐
     │     CI Workflow      │
     │  fmt → lint → SAST  │
     │  plan (dev/stg/prod)│
     │  Comentário no PR   │
     └─────────┬───────────┘
               │
               ▼
     ┌─────────────────────┐
     │   Code Review        │
     │   Verifica plan      │
     │   Verifica custos    │
     │   Verifica segurança │
     └─────────┬───────────┘
               │ Aprovado 
               ▼
     ┌─────────────────────┐
     │   Merge para main    │
     └─────────┬───────────┘
               │
               ▼
     ┌─────────────────────┐
     │     CD Workflow      │
     │  Tag: v1.2.4         │
     │  Apply: dev (auto)   │
     │  Apply: stg (manual) │ ← Precisa aprovação
     │  Apply: prod (manual)│ ← Precisa aprovação + 10min
     │  Slack:  Deploy     │
     └─────────────────────┘

     ... Domingo 8h UTC ...

     ┌─────────────────────┐
     │  Security Weekly     │
     │  kube-bench → CIS   │
     │  Popeye → Sanidade  │
     │  Kubescape → NSA    │
     └─────────────────────┘
```

---

##  Conceitos para Estudar

| Conceito | O que é | Relevância |
|---------|---------|-----------|
| **GitHub Actions** | CI/CD nativo do GitHub | Automação de pipelines |
| **OIDC** | OpenID Connect — auth sem senhas | Segurança na AWS |
| **SARIF** | Static Analysis Results Interchange Format | Padrão de resultados de segurança |
| **Matrix strategy** | Executar jobs em paralelo para N combinações | Plan por ambiente |
| **Environment protection** | Regras de aprovação para deploys | Governance |
| **SemVer** | Semantic Versioning (major.minor.patch) | Versionamento |
| **CIS Benchmark** | Padrão de segurança da Center for Internet Security | Compliance |
| **SAST vs DAST** | Static vs Dynamic Application Security Testing | Segurança |
| **Checkov** | Scanner de IaC (Terraform, K8s, Docker) | SAST |
| **Trivy** | Scanner de vulnerabilidades multi-propósito | SAST |

---

[← Voltar ao README principal](../../README.md)
