################################################################################
# Secret Manager
#
# Terraform creates the secret *containers* and grants access.
# Actual secret values are populated separately (CI, manual, or rotation job)
# so they never appear in Terraform state or source code.
#
# To set a value after apply:
#   gcloud secrets versions add anthropic-api-key --data-file=- <<< "sk-ant-..."
################################################################################

resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "anthropic-api-key"
  project   = var.gcp_project

  replication {
    user_managed {
      replicas {
        location = var.gcp_region
      }
    }
  }

  labels = {
    managed-by = "terraform"
    component  = "agentic-sre"
  }
}

# Placeholder version — the CI pipeline overwrites this with the real value
# sourced from the GitHub secret ANTHROPIC_API_KEY.
# We use ignore_changes so terraform never overwrites a value set by CI.
resource "google_secret_manager_secret_version" "anthropic_api_key_placeholder" {
  secret      = google_secret_manager_secret.anthropic_api_key.id
  secret_data = "PLACEHOLDER_REPLACED_BY_CI"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# ── Additional secrets (add more here as the platform grows) ─────────────────
# Example pattern for a future Jira API token:
#
# resource "google_secret_manager_secret" "jira_api_token" {
#   secret_id = "jira-api-token"
#   project   = var.gcp_project
#   replication { user_managed { replicas { location = var.gcp_region } } }
# }
