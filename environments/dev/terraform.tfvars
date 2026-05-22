tenant      = "acme-corp"
environment = "dev"

vpc = {
  cidr               = "10.10.0.0/16"
  azs                = ["us-east-1a", "us-east-1b"]
  public_subnets     = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnets    = ["10.10.10.0/24", "10.10.11.0/24"]
  enable_nat_gateway = false # Sem NAT para economizar
  single_nat_gateway = true
}

tags = {
  CostCenter = "engineering"
  Project    = "saas-multi-tenant"
  Terraform  = "true"
}
