################################################################################
# Bootstrap — run ONCE manually with a user account that has Project Owner.
#
# Provisions:
#   1. Required GCP APIs
#   2. GCS bucket for Terraform remote state
#   3. Artifact Registry repository for Docker images
#   4. Cloud Build service account + IAM roles
#   5. Cloud Build trigger (push to main → cloudbuild.yaml)
#   6. GitHub Actions Workload Identity Federation (for PR-only CI workflow)
#
# Run:
#   cd deploy/bootstrap
#   cp terraform.tfvars.example terraform.tfvars
#   terraform init && terraform apply
#
# After apply, note the outputs and follow SETUP.md.
################################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # Bootstrap state is intentionally LOCAL — this is the one-time setup that
  # creates the GCS bucket used by every other terraform module.
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# ── Enable required GCP APIs ─────────────────────────────────────────────────

locals {
  bootstrap_apis = [
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "run.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "cloudtasks.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}

resource "google_project_service" "bootstrap_apis" {
  for_each           = toset(local.bootstrap_apis)
  project            = var.gcp_project
  service            = each.value
  disable_on_destroy = false
}

# ── GCS bucket for Terraform remote state ────────────────────────────────────

resource "google_storage_bucket" "tfstate" {
  name                        = var.tfstate_bucket_name
  project                     = var.gcp_project
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  # Retain only the 10 most recent state versions to control storage costs
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.bootstrap_apis]
}

# ── Artifact Registry repository ─────────────────────────────────────────────

resource "google_artifact_registry_repository" "agentic_sre" {
  repository_id = var.artifact_registry_repo
  project       = var.gcp_project
  location      = var.gcp_region
  format        = "DOCKER"
  description   = "Agentic SRE Docker images"

  depends_on = [google_project_service.bootstrap_apis]
}

# ── Cloud Build service account ───────────────────────────────────────────────

resource "google_service_account" "cloudbuild" {
  account_id   = var.cloudbuild_sa_name
  display_name = "Cloud Build Deploy Service Account"
  project      = var.gcp_project

  depends_on = [google_project_service.bootstrap_apis]
}

locals {
  cloudbuild_roles = [
    "roles/run.admin",                       # Deploy / manage Cloud Run services
    "roles/artifactregistry.writer",         # Push Docker images
    "roles/storage.admin",                   # Read/write Terraform state in GCS
    "roles/secretmanager.admin",             # Create & version secrets
    "roles/datastore.owner",                 # Create Firestore databases & indexes
    "roles/pubsub.admin",                    # Create Pub/Sub topics & subscriptions
    "roles/cloudtasks.admin",                # Create Cloud Tasks queues
    "roles/iam.serviceAccountAdmin",         # Create the app service account
    "roles/iam.serviceAccountUser",          # Act-as app service account during deploy
    "roles/resourcemanager.projectIamAdmin", # Manage IAM bindings via terraform
    "roles/serviceusage.serviceUsageAdmin",  # Enable GCP APIs via terraform
    "roles/logging.admin",                   # Manage log sinks
    "roles/firebase.admin",                  # Manage Firestore TTL field policies
  ]
}

resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset(local.cloudbuild_roles)
  project  = var.gcp_project
  role     = each.value
  member   = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant object-level access to the tfstate bucket specifically
resource "google_storage_bucket_iam_member" "cloudbuild_tfstate" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Cloud Build SA must be able to read the anthropic-api-key secret.
# The secret is created by the main terraform on first deploy; until then this
# binding is created ahead of time so the trigger SA is ready.
resource "google_project_iam_member" "cloudbuild_secret_accessor" {
  project = var.gcp_project
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# ── Cloud Build trigger — push to main ───────────────────────────────────────

resource "google_cloudbuild_trigger" "deploy_main" {
  name     = "deploy-on-main"
  project  = var.gcp_project
  location = var.gcp_region

  description    = "Build, push image, run terraform apply, smoke test on push to main"
  service_account = google_service_account.cloudbuild.id

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _GCP_REGION             = var.gcp_region
    _ARTIFACT_REGISTRY_REPO = var.artifact_registry_repo
    _TF_STATE_BUCKET        = var.tfstate_bucket_name
    _TF_STATE_PREFIX        = "terraform/state"
    _LOG_LEVEL              = "INFO"
  }

  depends_on = [
    google_project_iam_member.cloudbuild_roles,
    google_storage_bucket_iam_member.cloudbuild_tfstate,
  ]
}

# ── GitHub Actions Workload Identity Federation (PR CI only) ─────────────────
# GitHub Actions runs tests + tf validate on pull requests.
# It uses WIF so no long-lived keys are stored in GitHub.

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  project                   = var.gcp_project
  display_name              = "GitHub Actions Pool"
  description               = "WIF pool for GitHub Actions PR checks (CI only)"

  depends_on = [google_project_service.bootstrap_apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  project                            = var.gcp_project
  display_name                       = "GitHub Actions Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  # Restrict to this specific repo — prevents other repos from using this pool
  attribute_condition = "attribute.repository == '${var.github_owner}/${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Dedicated SA for GitHub Actions PR checks (read-only needs — no deploy perms)
resource "google_service_account" "github_ci" {
  account_id   = var.github_ci_sa_name
  display_name = "GitHub Actions PR CI Service Account"
  project      = var.gcp_project
}

resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = google_service_account.github_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

# GitHub CI SA only needs to validate terraform (no state read needed for -backend=false)
# No project-level roles required for pure PR lint/test checks.
