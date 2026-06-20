locals {
  image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/${var.artifact_registry_repo}/agentic-sre:${var.image_tag}"
}

resource "google_cloud_run_v2_service" "agentic_sre" {
  name     = var.cloud_run_service_name
  location = var.gcp_region
  project  = var.gcp_project

  template {
    service_account = google_service_account.app.email

    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    max_instance_request_concurrency = var.cloud_run_concurrency

    containers {
      image = local.image

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle = true
      }

      # ── Non-sensitive configuration via env vars ──────────────────────────
      env {
        name  = "GCP_PROJECT"
        value = var.gcp_project
      }
      env {
        name  = "GCP_REGION"
        value = var.gcp_region
      }
      env {
        name  = "FIRESTORE_DATABASE"
        value = google_firestore_database.agentic_sre_db.name
      }
      env {
        name  = "PUBSUB_FALLBACK_TOPIC"
        value = google_pubsub_topic.fallback_alerts.name
      }
      env {
        name  = "CLOUD_TASKS_QUEUE"
        value = google_cloud_tasks_queue.incidents.name
      }
      env {
        name  = "LOG_LEVEL"
        value = var.log_level
      }

      # ── Secrets via Secret Manager (never in env literals) ────────────────
      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.anthropic_api_key.secret_id
            version = "latest"
          }
        }
      }

      ports {
        container_port = 8080
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    timeout = "${var.cloud_run_timeout_seconds}s"
  }

  depends_on = [
    google_project_iam_member.app_firestore_user,
    google_project_iam_member.app_pubsub_publisher,
    google_project_iam_member.app_tasks_enqueuer,
    google_project_iam_member.app_log_writer,
    google_secret_manager_secret_iam_member.app_anthropic_key,
    google_secret_manager_secret_version.anthropic_api_key_placeholder,
  ]
}

# Allow unauthenticated invocations so external alert systems can POST webhooks
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.gcp_project
  location = var.gcp_region
  name     = google_cloud_run_v2_service.agentic_sre.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
