tenant      = "acme-corp"
environment = "prod"

vpc = {
  cidr               = "10.30.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets     = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
  private_subnets    = ["10.30.10.0/24", "10.30.11.0/24", "10.30.12.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = false # NAT por AZ para HA
}

tags = {
  CostCenter  = "engineering"
  Project     = "saas-multi-tenant"
  Environment = "prod"
  Terraform   = "true"
}
