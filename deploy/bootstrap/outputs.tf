output "tfstate_bucket" {
  description = "GCS bucket for Terraform remote state"
  value       = google_storage_bucket.tfstate.name
}

output "artifact_registry_repo" {
  description = "Full Artifact Registry repo path for docker push/pull"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/${google_artifact_registry_repository.agentic_sre.repository_id}"
}

output "workload_identity_provider" {
  description = "WIF provider resource name — paste into GitHub secret WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "cicd_service_account" {
  description = "CI/CD service account email — paste into GitHub secret WIF_SERVICE_ACCOUNT"
  value       = google_service_account.cicd.email
}
