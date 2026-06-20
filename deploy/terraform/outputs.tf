output "cloud_run_url" {
  description = "Public URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.agentic_sre.uri
}

output "service_account_email" {
  description = "Application service account email"
  value       = google_service_account.app.email
}

output "firestore_database_name" {
  description = "Firestore database name"
  value       = google_firestore_database.agentic_sre_db.name
}

output "artifact_image_base" {
  description = "Base image path (without tag) for docker push"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/${var.artifact_registry_repo}/agentic-sre"
}

output "pubsub_fallback_topic" {
  description = "Pub/Sub fallback topic name"
  value       = google_pubsub_topic.fallback_alerts.name
}

output "cloud_tasks_queue" {
  description = "Cloud Tasks queue name"
  value       = google_cloud_tasks_queue.incidents.name
}

output "anthropic_secret_name" {
  description = "Secret Manager secret ID for the Anthropic API key"
  value       = google_secret_manager_secret.anthropic_api_key.secret_id
}
