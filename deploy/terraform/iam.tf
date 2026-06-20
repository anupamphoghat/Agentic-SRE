# IAM bindings for the application service account (principle of least privilege)

resource "google_project_iam_member" "app_firestore_user" {
  project = var.gcp_project
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_project_iam_member" "app_pubsub_publisher" {
  project = var.gcp_project
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_project_iam_member" "app_tasks_enqueuer" {
  project = var.gcp_project
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_project_iam_member" "app_log_writer" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Secret Manager accessor — scoped per secret, not project-wide
resource "google_secret_manager_secret_iam_member" "app_anthropic_key" {
  project   = var.gcp_project
  secret_id = google_secret_manager_secret.anthropic_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}
