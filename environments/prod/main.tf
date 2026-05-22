terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "tfstate-saas-multi-tenant"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-lock"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = var.tags
  }
}

module "tenant_network" {
  source = "../../modules/tenant-network"

  tenant      = var.tenant
  environment = var.environment
  vpc         = var.vpc
  tags        = var.tags
}
