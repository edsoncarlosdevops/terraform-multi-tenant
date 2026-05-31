#  Subnets Públicas 
resource "aws_subnet" "public" {
  count = length(var.vpc.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.vpc.public_subnets[count.index]
  availability_zone       = local.azs[count.index % length(local.azs)]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-public-${count.index + 1}"
    Tenant      = var.tenant
    Environment = var.environment
    Tier        = "public"
  })
}

#  Subnets Privadas 
resource "aws_subnet" "private" {
  count = length(var.vpc.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.vpc.private_subnets[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-private-${count.index + 1}"
    Tenant      = var.tenant
    Environment = var.environment
    Tier        = "private"
  })
}
