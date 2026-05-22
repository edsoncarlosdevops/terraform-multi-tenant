output "cluster_id" {
  description = "ID do cluster EKS"
  value       = aws_eks_cluster.this.id
}

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "ID do security group do cluster"
  value       = aws_security_group.cluster.id
}

output "cluster_certificate_authority_data" {
  description = "Dados do certificado CA do cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_arn" {
  description = "ARN do cluster EKS"
  value       = aws_eks_cluster.this.arn
}

output "karpenter_role_arn" {
  description = "ARN da IAM Role do Karpenter"
  value       = try(aws_iam_role.karpenter[0].arn, "")
}

output "node_role_arn" {
  description = "ARN da IAM Role dos nodes"
  value       = aws_iam_role.node.arn
}

output "kms_key_arn" {
  description = "ARN da KMS Key para criptografia do EKS"
  value       = aws_kms_key.eks.arn
}
