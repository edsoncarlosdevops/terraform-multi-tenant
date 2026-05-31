variable "tenant" {
  description = "Nome do tenant"
  type        = string
}

variable "environment" {
  description = "Ambiente de deploy"
  type        = string
}

variable "vpc" {
  description = "Configuração da VPC"
  type = object({
    cidr               = string
    azs                = list(string)
    public_subnets     = list(string)
    private_subnets    = list(string)
    enable_nat_gateway = optional(bool, true)
    single_nat_gateway = optional(bool, true)
  })
}

variable "tags" {
  description = "Tags para aplicar nos recursos"
  type        = map(string)
  default     = {}
}

variable "infra_version" {
  description = "Versão da infraestrutura (tag git) para rastreabilidade"
  type        = string
  default     = "prod"
}

variable "enable_karpenter" {
  description = "Habilitar Karpenter no cluster EKS"
  type        = bool
  default     = true
}

variable "karpenter_instance_families" {
  description = "Familias de instancia EC2 permitidas pelo Karpenter"
  type        = list(string)
  default     = ["m6i", "m6a", "m7i", "c6i", "c7i", "r6i"]
}

variable "argocd_domain" {
  description = "Domínio para acesso ao ArgoCD (obrigatório em prod)"
  type        = string
  default     = ""
}
