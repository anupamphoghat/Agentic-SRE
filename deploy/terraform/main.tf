terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# ──────────────────────────────────────────────
# Service Account for Cloud Run
# ──────────────────────────────────────────────

resource "google_service_account" "agentic_sre_sa" {
  account_id   = "agentic-sre-agent"
  display_name = "Agentic SRE Agent Service Account"
  project      = var.gcp_project
}

# ──────────────────────────────────────────────
# IAM Bindings
# ──────────────────────────────────────────────

# Firestore: read/write documents
resource "google_project_iam_member" "firestore_user" {
  project = var.gcp_project
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.agentic_sre_sa.email}"
}

# Pub/Sub: publish messages to fallback topic
resource "google_project_iam_member" "pubsub_publisher" {
  project = var.gcp_project
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.agentic_sre_sa.email}"
}

# Cloud Tasks: enqueue tasks for async incident processing
resource "google_project_iam_member" "tasks_enqueuer" {
  project = var.gcp_project
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.agentic_sre_sa.email}"
}

# Cloud Logging: write structured log entries
resource "google_project_iam_member" "log_writer" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.agentic_sre_sa.email}"
}

# ──────────────────────────────────────────────
# Firestore Database
# CRITICAL: type must be FIRESTORE_NATIVE
# DATASTORE_MODE does not support TTL policies,
# which are required for 60-min alert group cleanup.
# ──────────────────────────────────────────────

resource "google_firestore_database" "agentic_sre_db" {
  name        = "agentic-sre-db"
  project     = var.gcp_project
  location_id = var.gcp_region
  type        = "FIRESTORE_NATIVE"

  # Prevent accidental deletion of the database
  deletion_policy = "DELETE"
}

# TTL policy: automatically delete alert_groups after expires_at field
resource "google_firestore_field" "alert_groups_ttl" {
  project    = var.gcp_project
  database   = google_firestore_database.agentic_sre_db.name
  collection = "alert_groups"
  field      = "expires_at"

  ttl_config {}

  depends_on = [google_firestore_database.agentic_sre_db]
}

# ──────────────────────────────────────────────
# Pub/Sub Fallback Topic
# Buffers alerts when Cloud Run is unavailable
# ──────────────────────────────────────────────

resource "google_pubsub_topic" "fallback_alerts" {
  name    = "agentic-sre-fallback-alerts"
  project = var.gcp_project

  message_retention_duration = "86400s" # 24 hours
}

# Dead-letter topic for unprocessable messages
resource "google_pubsub_topic" "fallback_alerts_dead_letter" {
  name    = "agentic-sre-fallback-alerts-dead-letter"
  project = var.gcp_project
}

# Subscription for Cloud Run to pull from the fallback topic
resource "google_pubsub_subscription" "fallback_alerts_sub" {
  name    = "agentic-sre-fallback-alerts-sub"
  topic   = google_pubsub_topic.fallback_alerts.name
  project = var.gcp_project

  ack_deadline_seconds = 60

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.fallback_alerts_dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
}

# ──────────────────────────────────────────────
# Cloud Tasks Queue
# Async retry queue for Jira ticket creation
# ──────────────────────────────────────────────

resource "google_cloud_tasks_queue" "incidents" {
  name     = "agentic-sre-incidents"
  location = var.gcp_region
  project  = var.gcp_project

  rate_limits {
    max_dispatches_per_second = 10
    max_concurrent_dispatches = 5
  }

  retry_config {
    max_attempts  = 5
    min_backoff   = "10s"
    max_backoff   = "300s"
    max_doublings = 4
  }
}

# ──────────────────────────────────────────────
# Cloud Run Service
# ──────────────────────────────────────────────

resource "google_cloud_run_v2_service" "agentic_sre" {
  name     = "agentic-sre-agent"
  location = var.gcp_region
  project  = var.gcp_project

  template {
    service_account = google_service_account.agentic_sre_sa.email

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    containers {
      image = "gcr.io/${var.gcp_project}/agentic-sre:${var.image_tag}"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

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

    timeout = "60s"
  }

  depends_on = [
    google_project_iam_member.firestore_user,
    google_project_iam_member.pubsub_publisher,
    google_project_iam_member.tasks_enqueuer,
    google_project_iam_member.log_writer,
  ]
}

# Allow unauthenticated invocations (webhooks from external alert systems)
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.gcp_project
  location = var.gcp_region
  name     = google_cloud_run_v2_service.agentic_sre.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
