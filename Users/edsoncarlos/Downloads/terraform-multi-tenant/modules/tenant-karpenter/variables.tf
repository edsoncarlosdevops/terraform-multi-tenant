variable "tenant" {
  description = "Nome do tenant"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "karpenter_role_arn" {
  description = "ARN da IAM Role do Karpenter"
  type        = string
}

variable "karpenter_version" {
  description = "Versão do Karpenter a ser instalada"
  type        = string
  default     = "1.0.12"
}

variable "karpenter_namespace" {
  description = "Namespace onde o Karpenter será instalado"
  type        = string
  default     = "kube-system"
}
