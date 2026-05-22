# 🔧 Configuração GitHub Actions + AWS

## 1. Criar IAM Role para GitHub Actions

Acesse o console AWS > IAM > Roles > Create Role.

### Trust Policy (OIDC)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "accounts.google.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### Passo a passo no console:
1. IAM > Identity Providers > Add Provider
2. Provider Type: OpenID Connect
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Audience: `sts.amazonaws.com`
5. Create Role:
   - Trusted entity type: Web identity
   - Identity provider: `token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
   - GitHub organization: `SEU_USUARIO`
   - GitHub repository: `terraform-multi-tenant`
6. Attach Policy: `AdministratorAccess` (ou uma custom mais restrita)
7. Role name: `github-actions-terraform`

## 2. Secrets no GitHub

Settings > Secrets and variables > Actions > New repository secret:

| Secret | Valor |
|--------|-------|
| `AWS_ACCOUNT_ID` | Seu ID da conta AWS (12 dígitos) |
| `SLACK_WEBHOOK` | (opcional) Webhook do Slack |
| `INFRACOST_API_KEY` | (opcional) API key do Infracost |

## 3. Environments no GitHub

Settings > Environments > New Environment:

### dev
- Sem protection rules (deploy automático)

### staging
- Required reviewers: adicione seu usuario
- Wait timer: 0 minutos

### prod
- Required reviewers: adicione seu usuario
- Wait timer: 10 minutos (delay antes de aplicar)

## 4. Testando

```bash
# 1. Crie um branch
git checkout -b test/ci

# 2. Algo simples (mude uma tag)
# 3. Commit e push
git add . && git commit -m "test: ci pipeline" && git push origin test/ci

# 4. Abra PR no GitHub
# 5. Veja os checks rodando
# 6. Merge quando tudo passar
```
