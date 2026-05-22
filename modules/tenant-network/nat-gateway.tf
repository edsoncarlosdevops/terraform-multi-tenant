# ─── Elastic IP para NAT Gateway ────────────────────────────────
resource "aws_eip" "nat" {
  count = var.vpc.single_nat_gateway ? 1 : length(local.azs)

  domain = "vpc"

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-nat-eip"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

# ─── NAT Gateway ────────────────────────────────────────────────
resource "aws_nat_gateway" "this" {
  count = var.vpc.enable_nat_gateway ? (var.vpc.single_nat_gateway ? 1 : length(local.azs)) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index % length(aws_subnet.public)].id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-nat-${count.index + 1}"
    Tenant      = var.tenant
    Environment = var.environment
  })

  depends_on = [aws_internet_gateway.this]
}
