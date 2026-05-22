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

output "vpc_flow_log_group" {
  description = "Nome do CloudWatch Log Group para flow logs"
  value       = try(module.tenant_network.vpc_flow_log_group, "")
}
