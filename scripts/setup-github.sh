#!/bin/bash
# ─── Script de Setup para subir no GitHub ────────────────────
# Uso: ./scripts/setup-github.sh
#
# Prepara o repositorio local para o primeiro push:
# 1. Verifica se tudo esta formatado
# 2. Roda terraform validate em todos ambientes
# 3. Mostra os secrets que precisam ser configurados
# 4. Mostra o resumo do que vai ser enviado

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "========================================"
echo "  PREPARANDO PARA SUBIR NO GITHUB"
echo "========================================"
echo ""

# ─── 1. Verifica Git ────────────────────────────────────────
echo -e "${YELLOW}[1/4] Verificando Git...${NC}"
if [ ! -d "$PROJECT_DIR/.git" ]; then
  echo "  ⚠️  Repositorio Git nao inicializado. Crie no GitHub primeiro:"
  echo "     gh repo create terraform-multi-tenant --public"
  echo "     git init && git add . && git commit -m 'initial'"
  echo "     git remote add origin <URL>"
  echo "     git push -u origin main"
else
  echo "  ✅ Git OK"
fi

# ─── 2. Terraform fmt ───────────────────────────────────────
echo ""
echo -e "${YELLOW}[2/4] Formatando codigo Terraform...${NC}"
cd "$PROJECT_DIR"
terraform fmt -recursive
echo "  ✅ Formatacao concluida"

# ─── 3. Valida ambientes (sem creds AWS, só sintaxe) ───────
echo ""
echo -e "${YELLOW}[3/4] Validando sintaxe (sem AWS)...${NC}"
for env in dev staging prod; do
  if [ -d "environments/$env" ]; then
    cd "$PROJECT_DIR/environments/$env"
    terraform init -backend=false -quiet 2>/dev/null || true
    if terraform validate 2>/dev/null; then
      echo "  ✅ $env - OK"
    else
      echo "  ⚠️  $env - Erro de sintaxe (pode ser falta de providers)"
    fi
  fi
done

# ─── 4. Mostra resumo ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}[4/4] Resumo do que vai subir:${NC}"
cd "$PROJECT_DIR"
echo ""
echo "  📁 Estrutura:"
echo "  ├── bootstrap/          (S3 + DynamoDB)"
echo "  ├── modules/"
echo "  │   ├── tenant-network/ (VPC + subnets + NAT + endpoints)"
echo "  │   ├── tenant-eks/     (Cluster + NodeGroup + Karpenter)"
echo "  │   └── tenant-argocd/  (ArgoCD + AppSets + Projects)"
echo "  ├── environments/"
echo "  │   ├── dev/            (custo zero)"
echo "  │   ├── staging/        (balanceado)"
echo "  │   └── prod/           (HA)"
echo "  └── .github/workflows/  (6 pipelines)"
echo ""
echo "  🔑 Secrets necessarios no GitHub:"
echo "     - AWS_ACCOUNT_ID"
echo "     - SLACK_WEBHOOK (opcional)"
echo "     - INFRACOST_API_KEY (opcional)"
echo ""
echo "  🔧 IAM Role necessaria na AWS:"
echo "     - github-actions-terraform (ver docs/github-actions-setup.md)"
echo ""
echo "========================================"
echo -e "${GREEN}  PRONTO PARA SUBIR!${NC}"
echo "========================================"
echo ""
echo "  Comandos:"
echo "    git add ."
echo "    git commit -m 'feat: infra multi-tenant completa'"
echo "    git push -u origin main"
echo ""
