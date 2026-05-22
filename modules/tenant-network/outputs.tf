output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "azs" {
  value = local.azs
}

output "nat_gateway_ids" {
  value = try(aws_nat_gateway.this[*].id, [])
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "vpc_flow_log_group" {
  value = try(aws_cloudwatch_log_group.flow_logs[0].name, "")
}

