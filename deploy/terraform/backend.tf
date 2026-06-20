terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    # Bucket name is passed via -backend-config in CI or via terraform init -backend-config=...
    # Keeping bucket/prefix out of source so the same code can target different environments.
    # CI sets: -backend-config="bucket=agentic-sre-500001-tfstate" -backend-config="prefix=terraform/state"
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
