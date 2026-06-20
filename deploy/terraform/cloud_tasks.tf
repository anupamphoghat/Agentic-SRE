resource "google_cloud_tasks_queue" "incidents" {
  name     = var.cloud_tasks_queue_name
  location = var.gcp_region
  project  = var.gcp_project

  rate_limits {
    max_dispatches_per_second = var.cloud_tasks_max_dispatches_per_second
    max_concurrent_dispatches = var.cloud_tasks_max_concurrent_dispatches
  }

  retry_config {
    max_attempts  = var.cloud_tasks_max_attempts
    min_backoff   = "10s"
    max_backoff   = "300s"
    max_doublings = 4
  }
}
