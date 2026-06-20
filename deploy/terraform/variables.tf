# ── Project ──────────────────────────────────────────────────────────────────

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "Primary GCP region for all resources"
  type        = string
  default     = "us-central1"
}

# ── Image ─────────────────────────────────────────────────────────────────────

variable "image_tag" {
  description = "Docker image tag to deploy to Cloud Run (injected by CI)"
  type        = string
  default     = "latest"
}

variable "artifact_registry_repo" {
  description = "Artifact Registry repository ID"
  type        = string
  default     = "agentic-sre"
}

# ── Cloud Run ─────────────────────────────────────────────────────────────────

variable "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "agentic-sre-agent"
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "cloud_run_cpu" {
  description = "vCPU allocation per Cloud Run instance"
  type        = string
  default     = "1"
}

variable "cloud_run_memory" {
  description = "Memory allocation per Cloud Run instance"
  type        = string
  default     = "512Mi"
}

variable "cloud_run_timeout_seconds" {
  description = "Request timeout for Cloud Run (seconds)"
  type        = number
  default     = 60
}

variable "cloud_run_concurrency" {
  description = "Max concurrent requests per Cloud Run instance"
  type        = number
  default     = 80
}

# ── Application ───────────────────────────────────────────────────────────────

variable "log_level" {
  description = "Application log level (DEBUG | INFO | WARNING | ERROR)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "log_level must be one of: DEBUG, INFO, WARNING, ERROR"
  }
}

variable "firestore_database_name" {
  description = "Firestore database name"
  type        = string
  default     = "agentic-sre-db"
}

variable "alert_group_ttl_minutes" {
  description = "Alert group TTL in minutes — documents are auto-deleted after this period of silence"
  type        = number
  default     = 60
}

# ── Pub/Sub ───────────────────────────────────────────────────────────────────

variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub fallback alerts topic"
  type        = string
  default     = "agentic-sre-fallback-alerts"
}

variable "pubsub_message_retention_seconds" {
  description = "How long Pub/Sub retains unacknowledged messages (seconds)"
  type        = number
  default     = 86400 # 24 hours
}

variable "pubsub_max_delivery_attempts" {
  description = "Max delivery attempts before moving to dead-letter topic"
  type        = number
  default     = 5
}

# ── Cloud Tasks ───────────────────────────────────────────────────────────────

variable "cloud_tasks_queue_name" {
  description = "Name of the Cloud Tasks queue for async incident creation"
  type        = string
  default     = "agentic-sre-incidents"
}

variable "cloud_tasks_max_dispatches_per_second" {
  description = "Max task dispatches per second"
  type        = number
  default     = 10
}

variable "cloud_tasks_max_concurrent_dispatches" {
  description = "Max concurrent task dispatches"
  type        = number
  default     = 5
}

variable "cloud_tasks_max_attempts" {
  description = "Max retry attempts for a failed task"
  type        = number
  default     = 5
}

# ── Service Account ───────────────────────────────────────────────────────────

variable "app_sa_name" {
  description = "Service account ID for the Cloud Run application"
  type        = string
  default     = "agentic-sre-agent"
}
