# Infrastructure Setup Guide

## Architecture

| Trigger | Tool | What runs |
|---------|------|-----------|
| Push to `main` | **Cloud Build** | test → docker build/push → terraform plan/apply → smoke test |
| Pull Request | **GitHub Actions** | pytest, terraform fmt/validate |

Terraform state is stored in a GCS bucket (`agentic-sre-500001-tfstate`).
State is injected at `terraform init` time via `-backend-config` so the same
code can target different environments without changing source files.

---

## Prerequisites

- GCP project `agentic-sre-500001` created with billing enabled
- `gcloud` CLI authenticated as Project Owner: `gcloud auth application-default login`
- `terraform` >= 1.6 installed
- GitHub repo connected to Google Cloud Build (one-time OAuth step in GCP Console)

---

## Step 1 — Connect GitHub to Cloud Build

In GCP Console → Cloud Build → Triggers → Connect Repository:
- Select **GitHub (Cloud Build GitHub App)**
- Authenticate and select `anupamphoghat/Agentic-SRE`

This only needs to be done once. The bootstrap terraform then creates the trigger automatically.

---

## Step 2 — Bootstrap (run once, manually)

Bootstrap provisions all prerequisites using a local Terraform state file.

```bash
cd deploy/bootstrap
cp terraform.tfvars.example terraform.tfvars  # values already filled for agentic-sre-500001
terraform init
terraform apply
```

This creates:
- GCS bucket `agentic-sre-500001-tfstate` (versioned, lifecycle-managed)
- Artifact Registry repo `agentic-sre` in `us-central1`
- Cloud Build service account `cloudbuild-deploy@...` with deployment roles
- Cloud Build trigger `deploy-on-main` pointing at `cloudbuild.yaml`
- Workload Identity Federation pool + provider for GitHub Actions PR checks
- GitHub Actions CI service account (read-only, for tf validate on PRs)

Note the outputs:
```
wif_provider             = "projects/.../providers/github-actions-provider"
github_ci_service_account = "github-actions-ci@agentic-sre-500001.iam.gserviceaccount.com"
```

---

## Step 3 — Seed the Anthropic API key in Secret Manager

The Cloud Build pipeline reads the key from Secret Manager. Set it once:

```bash
echo -n "sk-ant-YOUR_KEY_HERE" | \
  gcloud secrets versions add anthropic-api-key \
    --project=agentic-sre-500001 \
    --data-file=-
```

On first deploy the `terraform apply` step creates the secret container.
If the key hasn't been seeded yet, run the command above after the first build.

---

## Step 4 — Add GitHub Secrets (for PR CI checks only)

In GitHub → Settings → Secrets and variables → Actions:

| Secret | Value |
|--------|-------|
| `WIF_PROVIDER` | `wif_provider` output from Step 2 |
| `WIF_SERVICE_ACCOUNT` | `github_ci_service_account` output from Step 2 |

These are only used by the GitHub Actions PR workflow (terraform validate).
The deploy pipeline runs entirely in Cloud Build and does not need GitHub secrets.

---

## Step 5 — Trigger your first deploy

Push any commit to `main`:

```bash
git push origin main
```

Cloud Build picks it up automatically and runs `cloudbuild.yaml`:

1. **Unit tests** — pytest with ≥80% coverage gate
2. **Docker build** — tagged with `$SHORT_SHA` and `latest`
3. **Docker push** — to Artifact Registry
4. **terraform init** — GCS remote state backend
5. **terraform plan** — all infra changes previewed
6. **terraform apply** — infra deployed / updated
7. **Set secret** — writes `anthropic-api-key` from Secret Manager into app secret
8. **Smoke test** — `GET /health` must return 200

Monitor at: GCP Console → Cloud Build → History

---

## Local Development

```bash
# Run the app locally
pip install -r requirements.txt
export GCP_PROJECT=agentic-sre-500001
export ANTHROPIC_API_KEY=sk-ant-...
python main.py
curl http://localhost:8080/health

# Run tests
pytest tests/ -v

# Run terraform locally
cd deploy/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init \
  -backend-config="bucket=agentic-sre-500001-tfstate" \
  -backend-config="prefix=terraform/state"
terraform plan -var="image_tag=latest"
```

---

## Terraform state

- **Bucket**: `agentic-sre-500001-tfstate`
- **Prefix**: `terraform/state`
- **Versioning**: enabled (10 versions retained)
- **Auth**: Cloud Build SA uses `roles/storage.objectAdmin` on the bucket

To inspect state locally:
```bash
cd deploy/terraform
terraform init \
  -backend-config="bucket=agentic-sre-500001-tfstate" \
  -backend-config="prefix=terraform/state"
terraform show
```
