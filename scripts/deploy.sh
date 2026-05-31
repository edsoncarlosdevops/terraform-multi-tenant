#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# SCRIPT DE DEPLOY E CONFIGURAÇÃO AUTOMÁTICA (DEV)
# ═══════════════════════════════════════════════════════════════
# Este script automatiza o Terraform Apply do ambiente de DEV e
# realiza a configuração automática do seu kubeconfig local para
# conexão imediata com o cluster EKS recém-criado.
# ═══════════════════════════════════════════════════════════════

set -e

# Cores para saída de console
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Sem cor

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_DIR="$PROJECT_ROOT/environments/dev"

echo -e "${YELLOW}=== Iniciando o deploy do ambiente de desenvolvimento (DEV) ===${NC}"

# Ir para a pasta de desenvolvimento
cd "$DEV_DIR"

# 1. Inicializar o Terraform
echo -e "\n${GREEN}[1/3] Inicializando Terraform...${NC}"
terraform init

# 2. Executar o Deploy
echo -e "\n${GREEN}[2/3] Executando o Terraform Apply (Isso pode levar de 20 a 30 minutos)...${NC}"
terraform apply -auto-approve

# 3. Extrair os outputs e atualizar o kubeconfig
echo -e "\n${GREEN}[3/3] Configurando o acesso local ao cluster (Kubeconfig)...${NC}"

CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
REGION="us-east-1" # Regiao padrao definida no provider de dev

if [ -n "$CLUSTER_NAME" ]; then
    echo -e "${YELLOW}Cluster EKS detectado: $CLUSTER_NAME${NC}"
    echo -e "Executando: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
    echo -e "${GREEN}=== Deploy e configuração concluídos com sucesso! ===${NC}"
    echo -e "Você já pode rodar 'kubectl get nodes' para verificar os nós do cluster."
else
    echo -e "${RED}Erro: Não foi possível obter o nome do cluster a partir dos outputs do Terraform.${NC}"
    exit 1
fi
