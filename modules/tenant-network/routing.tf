#  Route Table Pública 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-public-rt"
    Tenant      = var.tenant
    Environment = var.environment
    Tier        = "public"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#  Route Tables Privadas 
resource "aws_route_table" "private" {
  count = var.vpc.single_nat_gateway ? 1 : length(local.azs)

  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.vpc.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.vpc.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
    }
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-private-rt-${count.index + 1}"
    Tenant      = var.tenant
    Environment = var.environment
    Tier        = "private"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.vpc.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index % length(local.azs)].id
}
