# ☸️ `tenant-eks` Module — Managed Kubernetes Cluster

[← Back to main README](../../../README.md)

---

## 📋 Overview

The `tenant-eks` module creates a **complete EKS cluster** with Node Groups, Karpenter for intelligent scaling, IAM Roles with least privilege, KMS encryption, and a wait mechanism to guarantee that the cluster is operational before installing additional components.

---

## 📁 Module Files

```
modules/tenant-eks/
├── main.tf               ← EKS Cluster + KMS Key + CloudWatch + Security Group
├── variables.tf          ← 14 variables (module contract)
├── providers.tf          ← kubectl provider (gavinbunney)
├── iam.tf                ← 3 IAM Roles (cluster, node, karpenter)
├── node-group.tf         ← Main On-Demand Node Group
├── karpenter.tf          ← EC2NodeClass + NodePool + Subnet Tags
├── wait-for-cluster.tf   ← Waits for cluster ACTIVE + nodes READY
└── outputs.tf            ← 9 outputs
```

---

## 📥 Input Variables (Contract)

```hcl
variable "tenant"                      { type = string }                    # "acme-corp"
variable "environment"                 { type = string }                    # "dev"
variable "vpc_id"                      { type = string }                    # From the tenant-network output
variable "private_subnet_ids"          { type = list(string) }             # From the tenant-network output
variable "kubernetes_version"          { type = string, default = "1.31" }
variable "node_instance_types"         { type = list(string), default = ["m6i.large", "m6a.large"] }
variable "node_disk_size"              { type = number, default = 50 }      # GB
variable "node_desired_size"           { type = number, default = 2 }
variable "node_min_size"               { type = number, default = 1 }
variable "node_max_size"               { type = number, default = 6 }
variable "enable_karpenter"            { type = bool, default = true }
variable "karpenter_instance_families" { type = list(string), default = ["m6i","m6a","m7i","c6i","c7i","r6i"] }
variable "tags"                        { type = map(string), default = {} }
```

**Why 14 variables?**
- Balance between **flexibility** (everything can be customized) and **smart defaults** (works without configuring anything)
- In dev, the defaults are already optimized for low cost

---

## 🔍 Detailed File Breakdown

### 1. `main.tf` — EKS Cluster

> ⚠️ **ATTENTION:** The EKS cluster takes **10-15 minutes** to become ACTIVE!

```hcl
resource "aws_eks_cluster" "this" {
  name     = "${local.name_prefix}-eks"      # E.g.: "acme-corp-dev-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version           # 1.31

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
}
```

#### Environment Configuration

| Configuration | Dev/Staging | Prod |
|--------|:-----------:|:----:|
| **Public endpoint** | ✅ (`0.0.0.0/0`) | ❌ |
| **Private endpoint** | ❌ | ✅ |
| **Enabled logs** | `api` (1 type) | 5 types (full) |
| **Log retention** | 7 days | 90 days |

**Why private endpoint in prod?**
- Reduces attack surface — API server only accessible from within the VPC
- Compliance: SOC2/HIPAA require controlled access to the control plane
- In dev/staging, public access facilitates local development with `kubectl`

#### KMS Key for Secrets

```hcl
resource "aws_kms_key" "eks" {
  description         = "EKS Secret Encryption Key - ${local.name_prefix}"
  enable_key_rotation = true     # ← Automatic annual rotation
}
```

**What is encrypted?**
- Kubernetes Secrets stored in etcd
- Without KMS, secrets are in plaintext in etcd
- With KMS, they are encrypted at rest

#### Cluster Security Group

```hcl
resource "aws_security_group" "cluster" {
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # Everything
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Why only egress?** Managed EKS automatically adds ingress rules between the control plane and the nodes. Defining it here is just a best practice to control egress.

---

### 2. `iam.tf` — 3 IAM Roles with Least Privilege

#### 🔵 Cluster Role (`eks-cluster-role`)

```
eks.amazonaws.com → AssumeRole → Policies:
├── AmazonEKSClusterPolicy        ← Manage the cluster
└── AmazonEKSVPCResourceController ← Manage ENIs for pods
```

#### 🟢 Node Role (`eks-node-role`)

```
ec2.amazonaws.com → AssumeRole → Policies:
├── AmazonEKSWorkerNodePolicy      ← Register node in the cluster
├── AmazonEKS_CNI_Policy           ← Manage network (VPC CNI)
├── AmazonEC2ContainerRegistryReadOnly ← ECR image pull
└── AmazonSSMManagedInstanceCore    ← Access via Session Manager (no SSH)
```

#### 🟠 Karpenter Role (`karpenter-role`) — Conditional

```
ec2.amazonaws.com → AssumeRole → Policies:
├── AmazonEKSWorkerNodePolicy      ← Register nodes
├── AmazonEKS_CNI_Policy           ← Network
├── AmazonEC2ContainerRegistryReadOnly ← ECR
├── AmazonSSMManagedInstanceCore    ← SSM
└── Custom Policy:                  ← Karpenter-specific
    ├── ec2:CreateLaunchTemplate
    ├── ec2:CreateFleet
    ├── ec2:RunInstances
    ├── ec2:CreateTags
    ├── ec2:TerminateInstances
    ├── ec2:Describe*
    ├── pricing:GetProducts
    └── iam:PassRole
```

**Why SSM instead of SSH?**
- No need to open port 22
- No need to manage SSH keys
- Native auditing via CloudTrail
- Access via AWS console or `aws ssm start-session`

---

### 3. `node-group.tf` — Main Node Group

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-ondemand"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types    # ["m6i.large", "m6a.large"]
  disk_size       = var.node_disk_size          # 50 GB

  scaling_config {
    desired_size = var.node_desired_size    # 2
    min_size     = var.node_min_size        # 1
    max_size     = var.node_max_size        # 6
  }

  labels = {
    "node-pool" = "ondemand"
    "critical"  = "true"
  }

  tags = {
    "k8s.io/cluster-autoscaler/${cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"         = "true"
  }
}
```

**Why On-Demand + labels?**
- Critical workloads (ArgoCD, controllers) run on the On-Demand node group
- Interruption-tolerant workloads go to Karpenter (Spot)
- Labels allow `nodeSelector` or `nodeAffinity` on pods

**In dev:** `min_size=1, max_size=2` to avoid spending on idle nodes.

---

### 4. `karpenter.tf` — Intelligent Scaling

> ⚠️ **IMPORTANT:** The Karpenter controller must be installed **SEPARATELY** via Helm chart. These manifests only **configure** the controller.

#### EC2NodeClass — Defines the machine "type"

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: acme-corp-dev
spec:
  amiFamily: AL2                        # Amazon Linux 2
  role: acme-corp-dev-karpenter-role    # IAM Role
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: acme-corp-dev    # ← Discovers subnets by tag
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: acme-corp-dev
```

#### NodePool — Scaling rules

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: ["m6i", "m6a", "m7i", "c6i", "c7i", "r6i"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]       # ← Prioritizes Spot
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
  limits:
    cpu: 2          # Dev: max 2 vCPU (prevents surprise costs)
                    # Prod: max 100 vCPU
  disruption:
    consolidationPolicy: WhenUnderutilized    # ← Removes idle nodes
    expireAfter: 720h                          # ← Recycles every 30 days
```

#### Subnet Tags for Discovery

```hcl
resource "aws_ec2_tag" "karpenter_subnets" {
  for_each    = toset(var.private_subnet_ids)
  resource_id = each.key
  key         = "karpenter.sh/discovery"
  value       = local.name_prefix
}
```

**How Karpenter works:**

```
Pod Pending (no capacity)
        │
        ▼
Karpenter detects
        │
        ▼
Evaluates requirements (family, arch, capacity-type)
        │
        ▼
Chooses cheapest instance (Spot if possible)
        │
        ▼
Creates node → Pod scheduled → ✅

... 10 min unused ...
        │
        ▼
Consolidation: removes idle node → 💰
```

---

### 5. `wait-for-cluster.tf` — "Necessary Workaround"

> *"Workaround? Yes. But necessary."*

**The problem:** Terraform creates the EKS cluster and **immediately** attempts to apply the Karpenter/ArgoCD manifests. But the cluster is not operational yet.

**The solution:**

```hcl
resource "null_resource" "wait_for_cluster" {
  depends_on = [aws_eks_cluster.this]

  provisioner "local-exec" {
    command = <<EOF
      # 1. Waits for cluster to be ACTIVE
      aws eks wait cluster-active --name ${cluster_name} --region ${region}

      # 2. Updates local kubeconfig
      aws eks update-kubeconfig --name ${cluster_name} --region ${region}

      # 3. Waits for nodes to be READY (up to 5 minutes)
      for i in $(seq 1 30); do
        READY_NODES=$(kubectl get nodes --no-headers | grep -c "Ready")
        if [ "$READY_NODES" -ge 1 ]; then
          echo "✅ $READY_NODES node(s) Ready!"
          break
        fi
        sleep 10
      done
    EOF
  }
}

# Authentication token ONLY becomes available AFTER the wait
data "aws_eks_cluster_auth" "this" {
  name       = aws_eks_cluster.this.name
  depends_on = [null_resource.wait_for_cluster]
}
```

**Timeline:**

```
0 min  ─── aws_eks_cluster.this created (Terraform sends API call)
           Status: CREATING
5 min  ─── Control plane being provisioned
10 min ─── Status: ACTIVE
           wait_for_cluster: "✅ EKS Cluster ACTIVE!"
12 min ─── Node group provisioning EC2
15 min ─── wait_for_cluster: "✅ 2 node(s) Ready!"
           → Now, apply Karpenter + ArgoCD
```

---

### 6. `outputs.tf` — Exported Values

```hcl
output "cluster_id"                      # Cluster ID
output "cluster_name"                    # Name (e.g., acme-corp-dev-eks)
output "cluster_endpoint"               # API URL (https://...)
output "cluster_security_group_id"      # Control plane SG
output "cluster_certificate_authority_data"  # CA cert (base64)
output "cluster_arn"                     # Full ARN
output "karpenter_role_arn"             # Karpenter role ARN (empty if disabled)
output "node_role_arn"                  # Node role ARN
output "kms_key_arn"                    # KMS Key ARN
```

These outputs are used by the `tenant-argocd` module to configure the Helm/Kubectl providers.

---

## 📐 Component Diagram

```
┌──────────────────────────────────── EKS Cluster ──────────────────────────────────┐
│                                                                                    │
│   ┌─── Control Plane (AWS Managed) ──────────────────────────────────────────────┐ │
│   │  API Server ← endpoint (public in dev, private in prod)                      │ │
│   │  etcd ← encrypted with KMS Key                                               │ │
│   │  Logs → CloudWatch (7d dev / 90d prod)                                       │ │
│   └──────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                    │
│   ┌─── Node Group: On-Demand ──────────────┐  ┌─── Karpenter Nodes ────────────┐ │
│   │  Instances: m6i.large / m6a.large      │  │  Instances: m6i/m6a/m7i/c6i    │ │
│   │  Labels: node-pool=ondemand            │  │  Capacity: Spot + On-Demand    │ │
│   │  Labels: critical=true                 │  │  CPU Limit: 2 (dev) / 100 (prod)│ │
│   │  Scaling: min=1, desired=2, max=6      │  │  Consolidation: auto           │ │
│   │  Disk: 50 GB                           │  │  Expiry: 30 days               │ │
│   │  IAM: eks-node-role + SSM              │  │  IAM: karpenter-role           │ │
│   │                                         │  │                                │ │
│   │  [ArgoCD] [Controllers] [Criticals]    │  │  [Tenant Apps] [Spot Workloads]│ │
│   └─────────────────────────────────────────┘  └────────────────────────────────┘ │
│                                                                                    │
│   ┌─── IAM Roles ──────────────────────────────────────────────────────────────┐  │
│   │  🔵 Cluster Role → EKSClusterPolicy + VPCResourceController               │  │
│   │  🟢 Node Role    → WorkerNode + CNI + ECR + SSM                            │  │
│   │  🟠 Karpenter    → Node policies + Custom (EC2 Create/Terminate)           │  │
│   └────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                    │
│   ┌─── Security ───────────────────────────────────────────────────────────────┐  │
│   │  🔐 KMS Key (automatic rotation) → Secrets encryption                      │  │
│   │  🛡️ Security Group → Egress only (AWS manages ingress)                      │  │
│   └────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🧪 Example Usage

```hcl
module "tenant_eks" {
  source = "../../modules/tenant-eks"

  tenant             = "acme-corp"
  environment        = "dev"
  vpc_id             = module.tenant_network.vpc_id
  private_subnet_ids = module.tenant_network.private_subnet_ids
  enable_karpenter   = true

  # Smart defaults for dev:
  # kubernetes_version = "1.31"
  # node_instance_types = ["m6i.large", "m6a.large"]
  # node_desired_size = 2
  # node_min_size = 1
  # node_max_size = 6
  
  tags = {
    CostCenter = "engineering"
  }
}
```

---

## ⚠️ Troubleshooting

| Error | Cause | Solution |
|------|-------|---------|
| `Error: waiting for EKS Cluster` | Cluster takes 10-15 min | Wait and run `terraform apply` again |
| `no matches for kind EC2NodeClass` | Karpenter controller not installed | Install the Karpenter Helm chart first |
| `Unauthorized` | Token expired or invalid kubeconfig | `aws eks update-kubeconfig --name <cluster>` |
| `Error locking state` | Another apply is running | `terraform force-unlock <ID>` |
| Nodes `NotReady` | Nodes still provisioning | Wait 2-3 min after cluster is ACTIVE |

---

## 🧠 Concepts to Study

| Concept | What it is | Relevance |
|---------|---------|-----------|
| **EKS** | Elastic Kubernetes Service — Managed K8s by AWS | Cluster management |
| **Control Plane** | K8s masters (API server, etcd, scheduler) | Managed by AWS |
| **Node Group** | Group of EC2s running pods | Worker nodes |
| **Karpenter** | AWS next-generation auto-scaler | Replaces cluster-autoscaler |
| **Spot Instances** | EC2s with 60-90% discount (can be interrupted) | FinOps |
| **KMS** | Key Management Service — secret encryption | Security |
| **IAM Roles** | AWS identities with permissions | Least privilege |
| **IRSA** | IAM Roles for Service Accounts | Pod identity |
| **null_resource** | Terraform resource with no real state | Running scripts |
| **provisioner "local-exec"** | Runs local command during apply | Workarounds |

---

[← Back to main README](../../../README.md)
