data "aws_region" "current" {}

locals {
  name_prefix = "${var.tenant}-${var.environment}"
}

# ─── Cluster EKS ──────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = "${local.name_prefix}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.environment == "prod" ? true : false
    endpoint_public_access  = var.environment == "prod" ? false : true
    public_access_cidrs     = var.environment == "prod" ? [] : ["0.0.0.0/0"]
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = var.environment == "prod" ? [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ] : ["api"]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.vpc_resource_controller,
    aws_cloudwatch_log_group.eks
  ]
}

# ─── KMS Key para criptografia dos secrets do EKS ────────────
resource "aws_kms_key" "eks" {
  description         = "EKS Secret Encryption Key - ${local.name_prefix}"
  enable_key_rotation = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-kms"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.name_prefix}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ─── CloudWatch Logs para EKS ────────────────────────────────
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.name_prefix}-eks/cluster"
  retention_in_days = var.environment == "prod" ? 90 : 7

  tags = var.tags
}

# ─── Security Group do Cluster ───────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}
