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
