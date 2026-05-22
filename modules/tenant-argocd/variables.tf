variable "tenant" {
  description = "Nome do tenant"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "infra_version" {
  description = "Versão da infraestrutura (tag git) para rastreabilidade"
  type        = string
  default     = "dev"
}

variable "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "CA do cluster EKS"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "argocd_version" {
  description = "Versão do ArgoCD"
  type        = string
  default     = "7.8.0"
}

variable "admin_password_hash" {
  description = "Hash bcrypt da senha admin do ArgoCD"
  type        = string
  sensitive   = true
  default     = "$2a$10$dummy"
}

variable "domain" {
  description = "Domínio para acesso ao ArgoCD (ex: argocd.acme-corp.com)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags para aplicar nos recursos"
  type        = map(string)
  default     = {}
}

