output "tfstate_bucket" {
  description = "GCS bucket name for Terraform remote state"
  value       = google_storage_bucket.tfstate.name
}

output "artifact_registry_repo" {
  description = "Full Artifact Registry repo path for docker push/pull"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/${google_artifact_registry_repository.agentic_sre.repository_id}"
}

output "cloudbuild_trigger_name" {
  description = "Cloud Build trigger name (fires on push to main)"
  value       = google_cloudbuild_trigger.deploy_main.name
}

output "cloudbuild_service_account" {
  description = "Cloud Build deploy service account email"
  value       = google_service_account.cloudbuild.email
}

output "wif_provider" {
  description = "Workload Identity Provider name — paste into GitHub secret WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_ci_service_account" {
  description = "GitHub Actions CI service account email — paste into GitHub secret WIF_SERVICE_ACCOUNT"
  value       = google_service_account.github_ci.email
}
