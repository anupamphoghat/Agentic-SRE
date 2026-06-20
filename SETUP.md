# Infrastructure Setup Guide

## Prerequisites

- GCP project `agentic-sre-500001` created, billing enabled
- `gcloud` CLI authenticated as Project Owner
- `terraform` >= 1.6 installed
- `gh` CLI authenticated

---

## Step 1 — Bootstrap (run once, manually)

Bootstrap provisions the GCS state bucket, Artifact Registry, and Workload Identity Federation.
It uses a local Terraform state file (intentional — this is the chicken-and-egg setup).

```bash
cd deploy/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed, then:

terraform init
terraform apply
```

Note the outputs:
```
workload_identity_provider = "projects/.../providers/github-actions-provider"
cicd_service_account       = "github-actions-cicd@agentic-sre-500001.iam.gserviceaccount.com"
```

---

## Step 2 — Add GitHub Secrets & Variables

In GitHub → Settings → Secrets and variables → Actions:

### Secrets
| Name | Value |
|------|-------|
| `WIF_PROVIDER` | `workload_identity_provider` output from bootstrap |
| `WIF_SERVICE_ACCOUNT` | `cicd_service_account` output from bootstrap |
| `ANTHROPIC_API_KEY` | Your Anthropic API key (`sk-ant-...`) |

### Variables (optional overrides)
| Name | Default | Description |
|------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Application log level |
| `CLOUD_RUN_MIN_INSTANCES` | `0` | Minimum Cloud Run instances |
| `CLOUD_RUN_MAX_INSTANCES` | `10` | Maximum Cloud Run instances |
| `CLOUD_RUN_MEMORY` | `512Mi` | Memory per instance |
| `CLOUD_RUN_CPU` | `1` | vCPUs per instance |

---

## Step 3 — Create GitHub Environment

In GitHub → Settings → Environments → New environment:
- Name: `production`
- (Optional) Add required reviewers for manual approval before apply

---

## Step 4 — Push to main

```bash
git push origin main
```

The deploy workflow will:
1. Run tests
2. Build Docker image → push to Artifact Registry
3. `terraform plan`
4. `terraform apply` (via the `production` environment gate)
5. Set the Anthropic API key in Secret Manager
6. Run a smoke test against `/health`

---

## Local Development

To run terraform locally:

```bash
cd deploy/terraform
cp terraform.tfvars.example terraform.tfvars
# Fill in any overrides

terraform init \
  -backend-config="bucket=agentic-sre-500001-tfstate" \
  -backend-config="prefix=terraform/state"

terraform plan -var="image_tag=latest"
terraform apply -var="image_tag=latest"
```

To run the app locally:

```bash
pip install -r requirements.txt
export GCP_PROJECT=agentic-sre-500001
export ANTHROPIC_API_KEY=sk-ant-...
python main.py
curl http://localhost:8080/health
```
