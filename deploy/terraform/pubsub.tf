resource "google_pubsub_topic" "fallback_alerts" {
  name    = var.pubsub_topic_name
  project = var.gcp_project

  message_retention_duration = "${var.pubsub_message_retention_seconds}s"

  labels = {
    managed-by = "terraform"
    component  = "agentic-sre"
  }
}

resource "google_pubsub_topic" "fallback_alerts_dead_letter" {
  name    = "${var.pubsub_topic_name}-dead-letter"
  project = var.gcp_project

  labels = {
    managed-by = "terraform"
    component  = "agentic-sre"
  }
}

resource "google_pubsub_subscription" "fallback_alerts_sub" {
  name    = "${var.pubsub_topic_name}-sub"
  topic   = google_pubsub_topic.fallback_alerts.name
  project = var.gcp_project

  ack_deadline_seconds = 60

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.fallback_alerts_dead_letter.id
    max_delivery_attempts = var.pubsub_max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  labels = {
    managed-by = "terraform"
    component  = "agentic-sre"
  }
}
