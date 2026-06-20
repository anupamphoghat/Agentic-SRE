################################################################################
# Bootstrap — run ONCE manually with a user account that has Project Owner.
# Creates the prerequisites that the CI/CD pipeline depends on:
#   1. GCS bucket for Terraform remote state
#   2. Artifact Registry repository for Docker images
#   3. Workload Identity Federation (keyless GitHub → GCP auth)
#   4. CI/CD service account + IAM roles
#
# After running:
#   terraform output workload_identity_provider  → add to GitHub secret WIF_PROVIDER
#   terraform output cicd_service_account        → add to GitHub secret WIF_SERVICE_ACCOUNT
################################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # Bootstrap state stored locally — intentionally not in GCS (chicken-and-egg)
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# ── Enable required GCP APIs ────────────────────────────────────────────────

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

# ── GCS bucket for Terraform remote state ───────────────────────────────────

resource "google_storage_bucket" "tfstate" {
  name                        = var.tfstate_bucket_name
  project                     = var.gcp_project
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

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

# ── Workload Identity Federation ─────────────────────────────────────────────

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  project                   = var.gcp_project
  display_name              = "GitHub Actions Pool"
  description               = "Identity pool for GitHub Actions OIDC tokens"

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

  # Restrict to the specific repo — prevents other repos from impersonating this SA
  attribute_condition = "attribute.repository == '${var.github_owner}/${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ── CI/CD service account ────────────────────────────────────────────────────

resource "google_service_account" "cicd" {
  account_id   = var.cicd_sa_name
  display_name = "GitHub Actions CI/CD Service Account"
  project      = var.gcp_project
}

# Allow the GitHub Actions WIF pool to impersonate this SA
resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = google_service_account.cicd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

# ── IAM roles for the CI/CD service account ──────────────────────────────────

locals {
  cicd_roles = [
    "roles/run.admin",                       # Deploy / manage Cloud Run services
    "roles/artifactregistry.writer",         # Push Docker images
    "roles/storage.admin",                   # Read/write Terraform state bucket
    "roles/secretmanager.admin",             # Create / version secrets
    "roles/datastore.owner",                 # Create Firestore database & indexes
    "roles/pubsub.admin",                    # Create Pub/Sub topics & subscriptions
    "roles/cloudtasks.admin",                # Create Cloud Tasks queues
    "roles/iam.serviceAccountAdmin",         # Create application service accounts
    "roles/iam.serviceAccountUser",          # Act-as application service accounts
    "roles/resourcemanager.projectIamAdmin", # Set IAM bindings via terraform
    "roles/serviceusage.serviceUsageAdmin",  # Enable GCP APIs
    "roles/logging.admin",                   # Configure log sinks / metrics
    "roles/firebase.admin",                  # Manage Firestore TTL field policies
  ]
}

resource "google_project_iam_member" "cicd_roles" {
  for_each = toset(local.cicd_roles)
  project  = var.gcp_project
  role     = each.value
  member   = "serviceAccount:${google_service_account.cicd.email}"
}

# CI/CD SA needs object-level access to the tfstate bucket
resource "google_storage_bucket_iam_member" "cicd_tfstate" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cicd.email}"
}
