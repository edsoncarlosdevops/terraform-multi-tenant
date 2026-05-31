# 📜 Utility Scripts

[← Back to main README](../../README.md)

---

## 📋 Overview

The project includes 2 utility scripts to assist with the initial setup and local versioning:

```
scripts/
├── setup-github.sh   ← Prepares the repo for the first push
└── version.sh        ← Local SemVer versioning
```

---

## 🔧 Script 1: `setup-github.sh`

### Purpose

Prepares the local repository for the first push to GitHub. It automates checks that would otherwise have to be done manually.

### Usage

```bash
./scripts/setup-github.sh
```

### What it does (4 steps)

```
┌─────────────────────────────────────────────────────────┐
│  [1/4] Checking Git...                                  │
│  ✅ Git OK                                              │
│  (or ⚠️ with instructions to create the repo)            │
├─────────────────────────────────────────────────────────┤
│  [2/4] Formatting Terraform code...                     │
│  terraform fmt -recursive                               │
│  ✅ Formatting completed                                │
├─────────────────────────────────────────────────────────┤
│  [3/4] Validating syntax (without AWS)...               │
│  terraform init -backend=false                          │
│  terraform validate                                     │
│  ✅ dev - OK                                            │
│  ✅ staging - OK                                        │
│  ✅ prod - OK                                           │
├─────────────────────────────────────────────────────────┤
│  [4/4] Summary of what will be pushed:                  │
│                                                         │
│  📁 Structure:                                          │
│  ├── bootstrap/          (S3 + DynamoDB)                │
│  ├── modules/                                           │
│  │   ├── tenant-network/ (VPC + subnets + NAT)          │
│  │   ├── tenant-eks/     (Cluster + NodeGroup)          │
│  │   └── tenant-argocd/  (ArgoCD + AppSets)             │
│  ├── environments/                                      │
│  │   ├── dev/            (zero cost)                    │
│  │   ├── staging/        (balanced)                     │
│  │   └── prod/           (HA)                           │
│  └── .github/workflows/  (pipelines)                    │
│                                                         │
│  🔑 Required Secrets in GitHub:                         │
│     - AWS_ACCOUNT_ID                                    │
│     - SLACK_WEBHOOK (optional)                          │
│     - INFRACOST_API_KEY (optional)                      │
│                                                         │
│  🔧 Required IAM Role in AWS:                           │
│     - github-actions-terraform                          │
│                                                         │
│  ════════════════════════════════════════                │
│  READY TO PUSH!                                         │
│  ════════════════════════════════════════                │
│                                                         │
│  Commands:                                              │
│    git add .                                            │
│    git commit -m 'feat: complete multi-tenant infra'    │
│    git push -u origin main                              │
└─────────────────────────────────────────────────────────┘
```

### Technical Details

```bash
set -euo pipefail    # ← Aborts on any error
```

| Flag | Meaning |
|------|-----------|
| `-e` | Exit on error — any command that fails stops the script |
| `-u` | Unset variables — using an undeclared variable is an error |
| `-o pipefail` | Pipe fail — if any command in a pipe fails, the entire pipe fails |

**`terraform init -backend=false`** — Initializes without connecting to the S3 backend. Allows syntax validation without AWS credentials.

**`terraform validate`** — Checks if the syntax is correct without creating any resources.

---

## 🏷️ Script 2: `version.sh`

### Purpose

Manages local SemVer (Semantic Versioning) versioning. Allows viewing, calculating, and creating tags without using CI/CD.

### Usage

```bash
# View current version
./scripts/version.sh current

# View next version (without creating)
./scripts/version.sh next

# Create and push the tag
./scripts/version.sh tag

# Help
./scripts/version.sh help
```

### Output Examples

```bash
$ ./scripts/version.sh current
📌 Current version: v1.2.3
🔑 Commit:          abc1234

$ ./scripts/version.sh next
📌 Last tag:     v1.2.3
📦 Next tag:     v1.2.4

To apply with this version:
  export TF_VAR_infra_version=v1.2.4
  terraform apply

$ ./scripts/version.sh tag
🏷️ Creating tag v1.2.4...
✅ Tag v1.2.4 created and pushed!
```

### Internal Functions

```bash
get_last_tag() {
  git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
}
```
- `git describe --tags --abbrev=0` → Returns the most recent annotated tag
- `2>/dev/null` → Suppresses the error if no tag exists
- `|| echo "v0.0.0"` → Fallback to v0.0.0 if there are no tags

```bash
get_next_version() {
  local LAST_TAG=$1
  local MAJOR=$(echo "$LAST_TAG" | cut -d. -f1 | tr -d 'v')
  local MINOR=$(echo "$LAST_TAG" | cut -d. -f2)
  local PATCH=$(echo "$LAST_TAG" | cut -d. -f3)
  echo "v$MAJOR.$MINOR.$((PATCH + 1))"
}
```

**Version parsing:**
```
v1.2.3
│ │ │ └── PATCH = 3  → cut -d. -f3
│ │ └──── MINOR = 2  → cut -d. -f2
│ └────── MAJOR = 1  → cut -d. -f1 | tr -d 'v' (removes 'v')
└──────── Prefix removed by tr -d
```

**Increment:** Always increments the PATCH (`$((PATCH + 1))`). To increment MINOR or MAJOR, do it manually.

### SemVer Explained

```
v MAJOR . MINOR . PATCH
  │       │       │
  │       │       └── Bug fixes (backward compatible)
  │       └────────── New feature (backward compatible)
  └────────────────── Breaking change (incompatible)

Examples:
  v1.2.3 → v1.2.4  (fix: route table adjustment)
  v1.2.4 → v1.3.0  (feat: new database module)
  v1.3.0 → v2.0.0  (BREAKING: change in the module interface)
```

### Terraform Integration

The `infra_version` is used for traceability:

```bash
# Via script
export TF_VAR_infra_version=$(./scripts/version.sh next | grep "Next tag" | awk '{print $NF}')
terraform apply

# Via CI/CD (automatic)
# cd.yml does this automatically:
env:
  TF_VAR_infra_version: ${{ needs.version.outputs.new_tag }}
```

Result in resources:
```yaml
# ArgoCD namespace will have:
metadata:
  labels:
    infra-version: "v1.2.4"     # ← Where did this namespace come from?
  annotations:
    infra.tenant.io/version: "v1.2.4"
```

---

## 🧠 Concepts to Study

| Concept | What it is | Relevance |
|---------|---------|-----------|
| **SemVer** | Semantic Versioning (`MAJOR.MINOR.PATCH`) | Versioning standard |
| **Git Tags** | Markers on commits | Releases |
| **`set -euo pipefail`** | Bash script strict mode | Robustness |
| **`terraform fmt`** | HCL automatic formatting | Standardization |
| **`terraform validate`** | Syntax validation | Quality gate |
| **`TF_VAR_*`** | Terraform environment variables | Value injection |
| **Annotated tags** | Tags with message (`git tag -a`) | Releases with metadata |

---

[← Back to main README](../../README.md)
