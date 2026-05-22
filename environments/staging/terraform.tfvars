tenant      = "acme-corp"
environment = "staging"

vpc = {
  cidr               = "10.20.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  private_subnets    = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true # Apenas 1 NAT para economizar
}

tags = {
  CostCenter  = "engineering"
  Project     = "saas-multi-tenant"
  Environment = "staging"
  Terraform   = "true"
}
