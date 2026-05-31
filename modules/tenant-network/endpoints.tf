#  VPC Endpoints para serviços AWS (economia de custo) 
# Evita tráfego via NAT Gateway -> reduz custos de dados transferidos

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.public.id]
  )

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-s3-endpoint"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.public.id]
  )

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-dynamodb-endpoint"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  count = var.environment == "prod" ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-ecr-api-endpoint"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.environment == "prod" ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-ecr-dkr-endpoint"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "logs" {
  count = var.environment == "prod" ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-logs-endpoint"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.environment == "prod" ? 1 : 0

  name        = "${local.name_prefix}-vpc-endpoints-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc.cidr]
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpc-endpoints-sg"
    Tenant      = var.tenant
    Environment = var.environment
  })
}
