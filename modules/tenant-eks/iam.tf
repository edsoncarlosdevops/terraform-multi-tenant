# 
# IAM: Roles, Policies e OIDC
# 
# Cria as IAM Roles necessarias para o cluster EKS:
#   - cluster     -> usada pelo EKS control plane
#   - node        -> usada pelos nodes do Node Group on-demand
#   - karpenter   -> usada pelos nodes CRIADOS pelo Karpenter
#   - karpenter_controller -> IRSA: usada pelo pod do Karpenter
#
# IMPORTANTE:
#   A role karpenter (EC2) e diferente da karpenter_controller
#   (Service Account). Nao confundir!
#
#   karpenter_role_arn           = role EC2 para nodes do Karpenter
#   karpenter_controller_role_arn = role IRSA para o controller
#
# CUSTO: IAM Roles sao gratuitas.
# 

#  IAM Role do Cluster 
# Usada pelo EKS control plane para gerenciar recursos AWS
# (ELBs, Security Groups, etc)
resource "aws_iam_role" "cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

#  IAM Role dos Nodes (Node Group on-demand) 
# Usada pelos nodes EC2 do Node Group gerenciado
# Permite: conexao com cluster, ECR, CNI, SSM
resource "aws_iam_role" "node" {
  name = "${local.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#  IAM Role dos Nodes do Karpenter 
#  DIFERENTE da role karpenter_controller!
# Esta role e usada pelas instancias EC2 que o Karpenter cria.
# A role karpenter_controller e usada pelo POD do Karpenter.
resource "aws_iam_role" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name = "${local.name_prefix}-karpenter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

#  OIDC Provider do EKS (para IRSA) 
# Necessario para IAM Roles for Service Accounts (IRSA)
# Permite que pods no cluster assumam IAM Roles especificas
# Custo: $0 (gratuito)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

#  IAM Role para IRSA do Karpenter (controller) 
#  ATENCAO: Esta role e ASSUMIDA pelo pod do Karpenter
# via WebIdentity (OIDC), NAO pelo EC2.
# Sem esta role, o Karpenter nao consegue criar instancias.
#
# Trust policy:
#   Principal: Federated = OIDC provider do EKS
#   Condition: service account karpenter no namespace kube-system
resource "aws_iam_role" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name = "${local.name_prefix}-karpenter-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:karpenter"
        }
      }
    }]
  })

  tags = var.tags
}

#  Attach policies na role karpenter_controller (IRSA) 
resource "aws_iam_role_policy_attachment" "karpenter_controller_worker" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_controller[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_cni" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_controller[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_ecr" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_controller[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_ssm" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_controller[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_custom" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter_controller[0].name
  policy_arn = aws_iam_policy.karpenter[0].arn
}

#  Attach policies na role karpenter (EC2) 
resource "aws_iam_role_policy_attachment" "karpenter_worker" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_cni" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_ecr" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_ssm" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#  Policy adicional do Karpenter (criar/taggear recursos) 
# Permite que o Karpenter crie EC2, Launch Templates, etc.
#  Se o Karpenter nao criar nodes, verifique esta policy!
resource "aws_iam_policy" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${local.name_prefix}-karpenter-policy"
  description = "Policy for Karpenter to manage EC2 instances and resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_custom" {
  count = var.enable_karpenter ? 1 : 0

  role       = aws_iam_role.karpenter[0].name
  policy_arn = aws_iam_policy.karpenter[0].arn
}
