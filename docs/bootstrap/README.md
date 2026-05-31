# 🔧 Bootstrap — Remote Backend (S3 + DynamoDB)

[← Back to main README](../../README.md)

---

## 📋 What is Bootstrap?

Bootstrap is the **first step** of the infrastructure. It creates the necessary resources for Terraform to store its **state remotely** and guarantee **locking** to prevent conflicts.

> ⚠️ **This module must be applied manually only ONCE**, before any other deployment.

---

## 🏗️ Created Resources

### 1. S3 Bucket — `tfstate-saas-multi-tenant`

The bucket stores the `.tfstate` files for all environments.

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "tfstate-saas-multi-tenant"
}
```

**Security configurations applied:**

| Configuration | Value | Why? |
|:------------|:------|:---------|
| **Versioning** | `Enabled` | Allows recovering previous states in case of corruption |
| **Encryption** | `AES256` (SSE-S3) | Protects the state at rest (contains sensitive data like ARNs, IPs) |
| **Public access block** | 4 flags enabled | Ensures that the bucket is never exposed publicly |

#### Versioning

```hcl
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

**Why version?**
- If someone runs `terraform destroy` accidentally, the previous state still exists
- Allows auditing historical changes in the state
- Facilitates rollback of corrupted states

#### Server-Side Encryption

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

**Why encrypt?**
- The `.tfstate` contains sensitive information (endpoints, ARNs, configurations)
- Compliance requirement (SOC2, HIPAA, PCI-DSS)
- `AES256` is the simplest and has no additional cost (vs KMS which charges per call)

#### Public Access Block

```hcl
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true   # Blocks new public ACLs
  block_public_policy     = true   # Blocks bucket policies that allow public access
  ignore_public_acls      = true   # Ignores existing public ACLs
  restrict_public_buckets = true   # Restricts public access to the bucket
}
```

### 2. DynamoDB Table — `tfstate-lock`

The table implements **state locking** to prevent two `terraform apply` runs from executing at the same time.

```hcl
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

**How locking works:**

```
┌──────────────────────────────────────────────────────┐
│  terraform apply (Terminal A)                        │
│    1. Writes LockID to DynamoDB                      │
│    2. Applies changes                                │
│    3. Removes LockID when finished                   │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  terraform apply (Terminal B — while A is running)   │
│    1. Tries to write LockID → CONFLICT!              │
│    2. Returns error: "Error locking state"           │
│    3. No changes are made                            │
└──────────────────────────────────────────────────────┘
```

**Why `PAY_PER_REQUEST`?**
- The lock is accessed only during `plan` and `apply`
- In most projects, there are few calls per day
- Practically zero cost (~$0.001/month)

---

## 📄 Files

### `bootstrap/provider.tf`

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

**Detail:** The bootstrap **does not use a remote backend** (chicken-and-egg problem). The bootstrap state remains local in `.terraform/` or can be imported later.

### `bootstrap/main.tf`

Contains the 4 resources described above (bucket, versioning, encryption, public block, DynamoDB table).

---

## 🚀 How to Use

### First time (setup)

```bash
cd bootstrap
terraform init
terraform apply -auto-approve
```

**Expected output:**
```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

### Verify created resources

```bash
# Verify bucket
aws s3 ls | grep tfstate

# Verify table
aws dynamodb describe-table --table-name tfstate-lock --query 'Table.TableStatus'
```

---

## 🔗 How Environments Use the Backend

Each environment references the backend created by the bootstrap:

```hcl
# environments/dev/main.tf
terraform {
  backend "s3" {
    bucket         = "tfstate-saas-multi-tenant"
    key            = "environments/dev/terraform.tfstate"    # ← unique path per environment
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-lock"                          # ← locking
  }
}
```

**S3 state structure:**

```
s3://tfstate-saas-multi-tenant/
├── environments/
│   ├── dev/terraform.tfstate
│   ├── staging/terraform.tfstate
│   └── prod/terraform.tfstate
```

---

## ⚠️ Precautions

| Scenario | What happens | How to resolve |
|---------|---------------|---------------|
| Delete the S3 bucket | State of ALL environments is lost | **Never delete**. If needed, import the state first |
| Delete the DynamoDB table | Locking stops working | Recreate the table with the same name and hash key |
| Stuck lock (apply crashed/hung) | No applies will work | `terraform force-unlock <LOCK_ID>` |
| Change bucket name | Environments lose reference to state | Update all `backend "s3"` configurations + migrate with `terraform init -migrate-state` |

---

## 🧠 Concepts to Study

| Concept | What it is | Link |
|---------|---------|------|
| **Terraform State** | File mapping real resources ↔ configuration | [docs](https://developer.hashicorp.com/terraform/language/state) |
| **Remote Backend** | Store state outside the local machine | [docs](https://developer.hashicorp.com/terraform/language/settings/backends/s3) |
| **State Locking** | Prevent simultaneous applies | [docs](https://developer.hashicorp.com/terraform/language/state/locking) |
| **S3 Versioning** | Keep S3 object history | [docs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html) |

---

[← Back to main README](../../README.md)
