data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  name_prefix = "${var.tenant}-${var.environment}"
  azs         = length(var.vpc.azs) > 0 ? var.vpc.azs : data.aws_availability_zones.available.names
}

# ─── VPC Principal ─────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpc"
    Tenant      = var.tenant
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─── Internet Gateway ───────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-igw"
    Tenant      = var.tenant
    Environment = var.environment
  })
}
