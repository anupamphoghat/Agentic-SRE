variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "Primary GCP region"
  type        = string
  default     = "us-central1"
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the repo (e.g. anupamphoghat)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. Agentic-SRE)"
  type        = string
}

variable "tfstate_bucket_name" {
  description = "GCS bucket name for Terraform remote state (must be globally unique)"
  type        = string
}

variable "artifact_registry_repo" {
  description = "Artifact Registry repository ID for Docker images"
  type        = string
  default     = "agentic-sre"
}

variable "cicd_sa_name" {
  description = "Service account ID used by GitHub Actions CI/CD"
  type        = string
  default     = "github-actions-cicd"
}
