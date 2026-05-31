output "vpc_id" {
  description = "ID da VPC"
  value       = module.tenant_network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas"
  value       = module.tenant_network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = module.tenant_network.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "IDs dos NAT Gateways"
  value       = module.tenant_network.nat_gateway_ids
}

output "eks_cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.tenant_eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = module.tenant_eks.cluster_endpoint
}

output "eks_cluster_arn" {
  description = "ARN do cluster EKS"
  value       = module.tenant_eks.cluster_arn
}

output "karpenter_role_arn" {
  description = "ARN da role do Karpenter"
  value       = module.tenant_eks.karpenter_role_arn
}

output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = module.tenant_argocd.argocd_namespace
}

output "argocd_server" {
  description = "URL do ArgoCD server"
  value       = module.tenant_argocd.argocd_server
}
