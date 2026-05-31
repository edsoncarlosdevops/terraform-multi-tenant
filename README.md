# 🏗️ SaaS Multi-Tenant Infrastructure — AWS + Terraform + EKS + ArgoCD

<p align="center">
  <img src="https://img.shields.io/badge/Terraform-%3E%3D1.6-7B42BC?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform">
  <img src="https://img.shields.io/badge/AWS-EKS%20%7C%20VPC%20%7C%20IAM-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white" alt="AWS">
  <img src="https://img.shields.io/badge/Kubernetes-1.31-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes">
  <img src="https://img.shields.io/badge/ArgoCD-7.8.0-EF7B4D?style=for-the-badge&logo=argo&logoColor=white" alt="ArgoCD">
  <img src="https://img.shields.io/badge/Karpenter-Spot%20%2B%20OnDemand-FF6B35?style=for-the-badge" alt="Karpenter">
  <img src="https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white" alt="CI/CD">
</p>

> 🇧🇷 [Leia em Português](README.pt-br.md)

<p align="center">
  <b>Production-ready SaaS infrastructure with full tenant isolation, GitOps, intelligent scaling, and layered security.</b>
</p>

<p align="center">
  <img src="docs/architecture/architecture-diagram.png" alt="Architecture Diagram" width="900">
</p>

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Documentation by Section](#-documentation-by-section)
- [Environment Comparison](#-environment-comparison)
- [CI/CD Pipeline](#-cicd-pipeline)
- [Security](#-security)
- [FinOps — Cost Optimization](#-finops--cost-optimization)
- [SemVer Versioning](#-semver-versioning)
- [Technology Stack](#-technology-stack)
- [Next Steps](#-next-steps)
- [License](#-license)

---

## 🎯 Overview

This project implements a **complete SaaS multi-tenant infrastructure on AWS** using the **Silo Model** (dedicated VPC per tenant). Each tenant receives its own isolated set of resources:

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Network** | VPC + Subnets + NAT + Endpoints | L3 network isolation per tenant |
| **Compute** | EKS + Managed Node Groups | AWS-managed Kubernetes |
| **Scaling** | Karpenter (Spot + On-Demand) | Intelligent auto-scaling with cost optimization |
| **GitOps** | ArgoCD + ApplicationSets | Declarative continuous deployment for multi-tenant |
| **State** | S3 + DynamoDB | Remote backend with state locking |
| **CI/CD** | GitHub Actions (3 workflows) | Plan, Apply, Security, Versioning |
| **Security** | Checkov, Trivy, Gitleaks, kube-bench | SAST on PRs + weekly DAST |

### 🔑 Key Design Decisions

- **Silo Model**: Each tenant gets a dedicated VPC → full isolation, no noisy neighbor
- **Reusable Modules**: 3 modules (`tenant-network`, `tenant-eks`, `tenant-argocd`) with lean contracts
- **Progressive Cost**: Dev ~$108/mo (1 NAT) → Staging = balanced → Prod = full HA
- **Native GitOps**: ArgoCD with ApplicationSets manages infra and tenant apps automatically
- **Layered Security**: SAST on every PR + weekly DAST on cluster

---

## 🏛️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GITHUB ACTIONS                                 │
│  ┌──────────┐  ┌───────────┐  ┌───────────┐  ┌──────────┐  ┌───────────┐    │
│  │ CI: Plan │  │ CD: Apply │  │  Security │  │ Infracost│  │ Tag/SemVer│    │
│  └────┬─────┘  └─────┬─────┘  └─────┬─────┘  └────┬─────┘  └─────┬─────┘    │
└───────┼──────────────┼──────────────┼──────────────┼──────────────┼────────-┘
        │              │              │              │              │
        └──────────────┴──────────────┴──────────────┴──────────────┘
                                      │
                              ┌───────┴───────┐
                              │  AWS Account  │
                              │  (us-east-1)  │
                              └───────┬───────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
   ┌────┴────┐                  ┌─────┴────┐                  ┌─────┴────┐
   │   DEV   │                  │ STAGING  │                  │   PROD   │
   │ 10.10.x │                  │ 10.20.x  │                  │ 10.30.x  │
   │  2 AZs  │                  │  3 AZs   │                  │  3 AZs   │
   │ NAT: 1  │                  │ NAT: 1   │                  │ NAT: 3   │
   └────┬────┘                  └────┬─────┘                  └────┬─────┘
        │                            │                             │
   ┌────┴────────────┐    ┌──────────┴──────────-┐   ┌─────────────┴────────-┐
   │  EKS Cluster    │    │  EKS Cluster         │   │  EKS Cluster          │
   │  + Karpenter    │    │  + Karpenter         │   │   + Karpenter         │
   │  + ArgoCD       │    │  + ArgoCD            │   │   + ArgoCD            │
   │  CPU limit: 2   │    │  CPU limit: 100      │   │   CPU limit: 100      │
   │  Logs: api only │    │  Logs: api only      │   │   Logs: full (5 types)│
   │  KMS: ✅        │    │  KMS: ✅              │   │   KMS: ✅ + Flow Logs │
   └─────────────────┘    └─────────────────────-┘   └──────────────────────-┘
```

### Data Flow

```
Developer → Git Push → PR → CI (lint + SAST + plan)
                            ↓ merge
                         CD (tag + apply + Slack)
                            ↓
                    ArgoCD detects changes
                            ↓
                   Automatic sync to pods
```

---

## 📁 Project Structure

```
terraform-multi-tenant/
│
├── 📄 README.md                              ← You are here
├── 📄 CODIGO_COMPLETO.txt                    ← Code reference dump
├── 📄 .gitignore                             ← Ignores .terraform, secrets, logs
│
├── 🔧 bootstrap/                            ← Initial setup (run once)
│   ├── main.tf                               │  S3 bucket + DynamoDB table
│   └── provider.tf                            │  AWS provider us-east-1
│
├── 📦 modules/                               ← Reusable modules
│   │
│   ├── 🌐 tenant-network/                   ← Network Module (8 files)
│   │   ├── main.tf                            │  VPC + Internet Gateway
│   │   ├── variables.tf                       │  4 variables (contract)
│   │   ├── subnets.tf                         │  Public + private subnets
│   │   ├── nat-gateway.tf                     │  Conditional NAT (0, 1, or N)
│   │   ├── routing.tf                         │  Route tables + associations
│   │   ├── endpoints.tf                       │  VPC Endpoints (Gateway + Interface)
│   │   ├── flow-logs.tf                       │  Flow Logs + IAM (prod only)
│   │   └── outputs.tf                         │  vpc_id, subnet_ids, nat_ids...
│   │
│   ├── ☸️  tenant-eks/                       ← EKS Module (8 files)
│   │   ├── main.tf                            │  EKS Cluster + KMS + CloudWatch + SG
│   │   ├── variables.tf                       │  14 variables (contract)
│   │   ├── providers.tf                       │  Kubectl provider (gavinbunney)
│   │   ├── iam.tf                             │  3 IAM Roles (cluster, node, karpenter)
│   │   ├── node-group.tf                      │  Primary On-Demand Node Group
│   │   ├── karpenter.tf                       │  EC2NodeClass + NodePool + Subnet Tags
│   │   ├── wait-for-cluster.tf                │  Waits for cluster ACTIVE + nodes READY
│   │   └── outputs.tf                         │  cluster_id, endpoint, ARNs...
│   │
│   └── 🔄 tenant-argocd/                    ← ArgoCD Module (9 files)
│       ├── variables.tf                       │  9 variables (contract)
│       ├── providers.tf                       │  Helm + Kubectl + Kubernetes
│       ├── version.tf                         │  Local infra_version
│       ├── namespace.tf                       │  argocd namespace with labels
│       ├── helm-release.tf                    │  ArgoCD Helm release
│       ├── values.yaml                        │  Values: RBAC, Ingress, Resources
│       ├── applicationsets.tf                 │  2 AppSets (tenants + infra)
│       ├── projects.tf                        │  2 AppProjects (infra + tenants)
│       └── outputs.tf                         │  namespace, server, appset names
│
├── 🌍 environments/                          ← Per-environment configurations
│   ├── dev/                                   │  Low cost: 1 NAT, no flow logs
│   │   ├── main.tf                            │  Orchestrator: network → EKS → ArgoCD
│   │   ├── variables.tf                       │  7 environment variables
│   │   ├── terraform.tfvars                   │  10.10.0.0/16, 2 AZs, NAT=true
│   │   └── outputs.tf                         │  10 outputs
│   ├── staging/                               │  Balanced: 1 NAT, basic endpoints
│   │   ├── main.tf                            │  Network module only (for now)
│   │   ├── variables.tf                       │  4 variables
│   │   ├── terraform.tfvars                   │  10.20.0.0/16, 3 AZs, NAT=1
│   │   └── outputs.tf                         │  4 outputs
│   └── prod/                                  │  Full HA: NAT per AZ, flow logs, endpoints
│       ├── main.tf                            │  Network module only (for now)
│       ├── variables.tf                       │  4 variables
│       ├── terraform.tfvars                   │  10.30.0.0/16, 3 AZs, NAT=3
│       └── outputs.tf                         │  5 outputs
│
├── ⚙️  .github/workflows/                   ← CI/CD Pipelines
│   ├── ci.yml                                 │  Unified CI: fmt + lint + SAST + plan
│   ├── cd.yml                                 │  Unified CD: tag + apply + Slack
│   └── security-weekly.yml                    │  Weekly DAST: kube-bench + Popeye
│
├── 📜 scripts/                               ← Utility scripts
│   ├── deploy.sh                              │  Automated deploy + kubeconfig setup
│   ├── setup-github.sh                        │  Prepares repo for first push
│   └── version.sh                             │  Local SemVer versioning
│
└── 📚 docs/                                  ← Additional documentation
    ├── github-actions-setup.md                │  Guide: IAM OIDC + Secrets + Environments
    ├── bootstrap/README.md                    │  Doc: S3/DynamoDB backend
    ├── modules/
    │   ├── tenant-network/README.md           │  Doc: Network module
    │   ├── tenant-eks/README.md               │  Doc: EKS module
    │   └── tenant-argocd/README.md            │  Doc: ArgoCD module
    ├── environments/README.md                 │  Doc: Dev/Staging/Prod environments
    ├── ci-cd/README.md                        │  Doc: GitHub Actions workflows
    ├── scripts/README.md                      │  Doc: Utility scripts
    └── architecture/README.md                 │  Doc: Architecture decisions
```

---

## ✅ Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| [Terraform](https://www.terraform.io/) | `>= 1.6` | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | `v2` | AWS authentication and configuration |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `1.29+` | Interaction with the EKS cluster |
| [Helm](https://helm.sh/) | `3.x` | ArgoCD installation |
| [Git](https://git-scm.com/) | `2.x` | Version control |

### AWS Account

- AWS account with permissions to create: VPC, EKS, IAM, KMS, CloudWatch, S3, DynamoDB
- Credentials configured: `aws configure` or IAM Role via OIDC (CI/CD)

---

## 🚀 Quick Start

### Step 1 — Bootstrap (run once)

Creates the remote backend (S3 + DynamoDB) to store Terraform state:

```bash
cd bootstrap
terraform init
terraform apply -auto-approve
```

> **What it creates:**
> - S3 Bucket `tfstate-saas-multi-tenant` (versioned, encrypted, public access blocked)
> - DynamoDB Table `tfstate-lock` (state locking)

### Step 2 — Deploy the Dev Environment

You can deploy the development environment either manually or automatically:

#### Option A: Automated Deploy (Recommended for local use)
Run the deploy script to apply Terraform and automatically configure your local `kubeconfig`:

```bash
./scripts/deploy.sh
```

#### Option B: Manual Deploy
1. Navigate to the environment directory:
   ```bash
   cd environments/dev
   ```
2. Initialize Terraform and apply the configuration:
   ```bash
   terraform init
   terraform apply -auto-approve
   ```
3. After completion, update your local `kubeconfig` to access the cluster:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name acme-corp-dev-eks
   ```

> ⚠️ **Estimated time:** ~20 to 30 minutes (EKS control plane provisioning, node startup, and ArgoCD installation take time).
>
> **Tip:** If the first apply fails (common due to IAM propagation delays during Kubernetes role creation), wait 2 minutes and run again.

### Step 3 — Deploy Staging/Prod

```bash
# Staging (balanced — 1 NAT)
cd environments/staging
terraform init
terraform apply -auto-approve

# Prod (HA — NAT per AZ, flow logs)
cd environments/prod
terraform init
terraform apply -auto-approve
```

### Step 4 — Destroy Resources

```bash
# Destroy a specific environment
cd environments/dev && terraform destroy -auto-approve
```

---

## 📖 Documentation by Section

Each project component has its own detailed documentation:

| Section | Link | Description |
|---------|------|-------------|
| 🔧 Bootstrap | [docs/bootstrap/README.md](docs/bootstrap/README.md) | S3 + DynamoDB backend, state locking, security |
| 🌐 Network Module | [docs/modules/tenant-network/README.md](docs/modules/tenant-network/README.md) | VPC, Subnets, NAT, Endpoints, Flow Logs |
| ☸️ EKS Module | [docs/modules/tenant-eks/README.md](docs/modules/tenant-eks/README.md) | EKS Cluster, Node Groups, Karpenter, IAM, KMS |
| 🔄 ArgoCD Module | [docs/modules/tenant-argocd/README.md](docs/modules/tenant-argocd/README.md) | ArgoCD, ApplicationSets, AppProjects, RBAC |
| 🌍 Environments | [docs/environments/README.md](docs/environments/README.md) | Dev, Staging, Prod — configurations and costs |
| ⚙️ CI/CD | [docs/ci-cd/README.md](docs/ci-cd/README.md) | Workflows: CI, CD, Security Weekly |
| 📜 Scripts | [docs/scripts/README.md](docs/scripts/README.md) | deploy.sh, setup-github.sh, version.sh |
| 🏛️ Architecture | [docs/architecture/README.md](docs/architecture/README.md) | Design decisions, Silo model, FinOps |

---

## 📊 Environment Comparison

| Feature | Dev | Staging | Prod |
|:--------|:---:|:-------:|:----:|
| **CIDR** | `10.10.0.0/16` | `10.20.0.0/16` | `10.30.0.0/16` |
| **AZs** | 2 | 3 | 3 |
| **Subnets (pub + priv)** | 2 + 2 | 3 + 3 | 3 + 3 |
| **NAT Gateway** | ✅ 1 (single) | ✅ 1 (single) | ✅ 3 (1 per AZ) |
| **VPC Endpoints Gateway** | ✅ S3 + DynamoDB | ✅ S3 + DynamoDB | ✅ S3 + DynamoDB |
| **VPC Endpoints Interface** | ❌ | ❌ | ✅ ECR + Logs |
| **Flow Logs** | ❌ | ❌ | ✅ (90 days) |
| **EKS Endpoint** | Public | Public | Private |
| **EKS Logs** | `api` | `api` | 5 types (full) |
| **CloudWatch Retention** | 7 days | 7 days | 90 days |
| **Karpenter CPU Limit** | 2 vCPU | 100 vCPU | 100 vCPU |
| **KMS Encryption** | ✅ | ✅ | ✅ |
| **CD Deploy** | Automatic | Manual approval | Approval + Freeze |
| **Estimated cost/mo** | ~$108 | ~$150 | ~$500+ |

---

## 🔄 CI/CD Pipeline

```
                    ┌────────────────────────────────┐
                    │      Developer creates PR      │
                    └──────────────┬─────────────────┘
                                   │
                    ┌──────────────▼─────────────────-┐
                    │   CI Workflow (ci.yml)          │
                    │                                 │
                    │  1. terraform fmt -check        │
                    │  2. tflint (lint)               │
                    │  3. Checkov (IaC scan)          │
                    │  4. Trivy (vuln + secrets)      │
                    │  5. Gitleaks (secrets scan)     │
                    │  6. terraform plan (per env)    │
                    │  7. PR comment with results     │
                    └──────────────┬─────────────────-┘
                                   │ merge
                    ┌──────────────▼────────────────-─┐
                    │   CD Workflow (cd.yml)          │
                    │                                 │
                    │  1. Calculate SemVer tag        │
                    │  2. Create automatic Git Tag    │
                    │  3. terraform apply (per env)   │
                    │  4. Slack notification          │
                    └───────────────────────────────-─┘

                    ┌────────────────────────────────-┐
                    │ Security Weekly (Sunday 8am)    │
                    │                                 │
                    │  1. kube-bench (CIS)            │
                    │  2. Popeye (cluster sanity)     │
                    │  3. Kubescape (NSA/CISA)        │
                    └────────────────────────────────-┘
```

---

## 🔒 Security

### SAST (Static Analysis — on every PR)

| Tool | Scope | Format |
|------|-------|--------|
| **Checkov** | IaC misconfigurations | SARIF → GitHub Security |
| **Trivy** | Vulnerabilities + secrets | SARIF → GitHub Security |
| **Gitleaks** | Secrets in code/history | GitHub native |
| **TFLint** | Terraform best practices | Compact |

### DAST (Dynamic Analysis — weekly)

| Tool | Scope | When |
|------|-------|------|
| **kube-bench** | CIS Kubernetes Benchmark | Sunday 8am UTC |
| **Popeye** | General cluster sanity | Sunday 8am UTC |
| **Kubescape** | NSA/CISA Framework | Sunday 8am UTC |

### Protection Layers

- **Network**: Isolated VPC per tenant, Security Groups, VPC Endpoints (no public traffic)
- **Secrets**: KMS Key with automatic rotation for EKS secrets encryption
- **IAM**: 3 Roles with least privilege (cluster, node, karpenter)
- **RBAC**: ArgoCD AppProjects with per-tenant restrictions
- **Endpoint**: In prod, EKS API server is private (no public access)

---

## 💰 FinOps — Cost Optimization

| Strategy | Impact | Where |
|----------|--------|-------|
| **Conditional NAT** | ~$108/mo in dev (1 NAT) vs ~$300/mo in prod (3 NATs) | `tenant-network` |
| **Gateway VPC Endpoints** | Free (S3/DynamoDB) | All environments |
| **Interface Endpoints only in prod** | ~$20/mo each | `endpoints.tf` |
| **Flow Logs only in prod** | ~$5/mo | `flow-logs.tf` |
| **Karpenter Spot** | 60-90% savings on nodes | `karpenter.tf` |
| **Karpenter Consolidation** | Removes idle nodes | `WhenUnderutilized` |
| **CPU Limit in dev** | Max 2 vCPU | `karpenter.tf` |
| **CloudWatch 7d in dev** | Reduces log costs | `main.tf` EKS |
| **CostCenter Tags** | Visibility per tenant | All resources |
| **Infracost on PRs** | Cost preview before merge | `ci.yml` |

---

## 🏷️ SemVer Versioning

The project uses automatic **Semantic Versioning**:

```bash
# View current version
./scripts/version.sh current

# View next version
./scripts/version.sh next

# Create and push tag
./scripts/version.sh tag
```

In CI/CD, the tag is automatically created on merge to `main` and passed as `TF_VAR_infra_version` to `terraform apply`.

---

## 🛠️ Technology Stack

| Category | Technologies |
|----------|-------------|
| **IaC** | Terraform >= 1.6 |
| **Cloud** | AWS (VPC, EKS, IAM, KMS, S3, DynamoDB, CloudWatch) |
| **Kubernetes** | EKS 1.31, Karpenter v1 (Spot + On-Demand) |
| **GitOps** | ArgoCD 7.8.0 with ApplicationSets |
| **CI/CD** | GitHub Actions (3 workflows) |
| **SAST** | Checkov, Trivy, TFLint, Gitleaks |
| **DAST** | kube-bench, Popeye, Kubescape |
| **Providers** | AWS ~> 5.0, Helm ~> 2.17, Kubernetes ~> 2.35, Kubectl ~> 1.14 |
| **Backend** | S3 + DynamoDB (state locking) |

---

## 📊 Next Steps

To make the SaaS infrastructure complete, the next modules would be:

| # | Module | Description |
|---|--------|-------------|
| 1 | `modules/tenant-compute` | ECS Fargate + ECR per tenant |
| 2 | `modules/tenant-database` | Aurora PostgreSQL / DynamoDB with `tenant_id` |
| 3 | `modules/tenant-auth` | Cognito User Pool + tenant claim in JWT |
| 4 | `modules/tenant-monitoring` | CloudWatch Dashboard per tenant |
| 5 | `modules/control-plane` | API Gateway + Lambda for tenant onboarding |
| 6 | `modules/tenant-billing` | AWS Budgets + Cost Tags per tenant |

---

## 📄 License

This project is open source and free to use for educational and professional purposes.

---

<p align="center">
  <i>"A Senior DevOps Engineer isn't someone who knows everything by heart.<br>
  It's someone who knows the right questions to ask and how to validate each step before moving forward."</i>
</p>
