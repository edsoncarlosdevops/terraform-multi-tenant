variable "tenant" {
  description = "Nome do tenant (ex: acme-corp, globo-saude)"
  type        = string
}

variable "environment" {
  description = "Ambiente de deploy (dev, staging, prod)"
  type        = string
}

variable "vpc" {
  description = "Configuração da VPC contendo CIDR, AZs, subnets públicas e privadas"
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
  description = "Tags para aplicar em todos os recursos"
  type        = map(string)
  default     = {}
}

