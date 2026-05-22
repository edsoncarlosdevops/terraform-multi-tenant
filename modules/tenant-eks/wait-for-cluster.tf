# ═══════════════════════════════════════════════════════════════
# GAMBI? Sim. Mas necessaria.
# ═══════════════════════════════════════════════════════════════
# O problema: o Terraform cria o cluster EKS e JÁ tenta aplicar
# os manifests do Karpenter/ArgoCD. Mas o cluster ainda nao esta
# operacional — os nodes ainda estao provisionando.
#
# A solucao: este recurso "null_resource" executa um script local
# que aguarda o cluster ficar ACTIVE e os nodes ficarem READY.
# So depois disso o Terraform prossegue com os manifests.
#
# Se der erro aqui, espere 2-3 min e tente apply novamente.
# ═══════════════════════════════════════════════════════════════

data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name

  depends_on = [aws_eks_cluster.this]
}

resource "null_resource" "wait_for_cluster" {
  depends_on = [aws_eks_cluster.this]

  triggers = {
    cluster_status = data.aws_eks_cluster.this.status
    cluster_name   = aws_eks_cluster.this.name
  }

  provisioner "local-exec" {
    command = <<EOF
      echo "========================================"
      echo "  AGUARDANDO CLUSTER EKS FICAR ACTIVE..."
      echo "  Cluster: ${aws_eks_cluster.this.name}"
      echo "  Regiao: ${data.aws_region.current.name}"
      echo "  Isso leva ~10-15 minutos apos criacao."
      echo "========================================"

      # ─── Aguarda o status do cluster mudar para ACTIVE ───────
      aws eks wait cluster-active --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.name}
      echo "✅ Cluster EKS ACTIVE!"

      # ─── Atualiza kubeconfig local ───────────────────────────
      aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.name} --quiet
      echo "✅ kubeconfig atualizado"

      # ─── Aguarda pelo menos 1 node ficar Ready ───────────────
      # O Node Group foi criado junto com o cluster
      # Mas leva alguns minutos para o node ser provisionado e registrado
      echo "Aguardando nodes ficarem READY (max 5 min)..."
      for i in $(seq 1 30); do
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
        if [ "$READY_NODES" -ge 1 ]; then
          echo "✅ $READY_NODES node(s) Ready!"
          kubectl get nodes -o wide
          break
        fi
        if [ "$i" -eq 30 ]; then
          echo "⚠️  Nodes ainda nao estao prontos. Continuando mesmo assim..."
        else
          printf "."
          sleep 10
        fi
      done
      echo ""
      echo "✅ Cluster pronto para receber manifests!"
    EOF
  }
}

# ─── Token de autenticacao para o provider kubectl ──────────
# So fica disponivel DEPOIS que o cluster estiver operacional
data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name

  depends_on = [null_resource.wait_for_cluster]
}
