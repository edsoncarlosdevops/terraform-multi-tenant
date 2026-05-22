variable "tenant" {
  description = "Nome do tenant"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde o cluster será criado"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas para os nodes"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "Tipos de instância para o node group principal"
  type        = list(string)
  default     = ["m6i.large", "m6a.large"]
}

variable "node_disk_size" {
  description = "Tamanho do disco dos nodes em GB"
  type        = number
  default     = 50
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de nodes"
  type        = number
  default     = 6
}

variable "enable_karpenter" {
  description = "Habilitar Karpenter para escalonamento automático"
  type        = bool
  default     = true
}

variable "karpenter_instance_families" {
  description = "Famílias de instância permitidas no Karpenter"
  type        = list(string)
  default     = ["m6i", "m6a", "m7i", "c6i", "c7i", "r6i"]
}

variable "tags" {
  description = "Tags para aplicar nos recursos"
  type        = map(string)
  default     = {}
}
