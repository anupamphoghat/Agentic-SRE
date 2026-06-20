output "cloud_run_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.agentic_sre.uri
}

output "service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.agentic_sre_sa.email
}

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.agentic_sre_db.name
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub fallback topic"
  value       = google_pubsub_topic.fallback_alerts.name
}

output "cloud_tasks_queue_name" {
  description = "Name of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.incidents.name
}
