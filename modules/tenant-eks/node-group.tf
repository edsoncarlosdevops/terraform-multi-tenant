#  Node Group Principal (On-Demand) 
# Usado para workloads críticas que não devem ser interrompidas
# O Karpenter gerencia o restante (spot, scaling dinâmico)

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-ondemand"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types
  disk_size       = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "node-pool" = "ondemand"
    "critical"  = "true"
  }

  tags = merge(var.tags, {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.this.name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"                      = "true"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
  ]
}
