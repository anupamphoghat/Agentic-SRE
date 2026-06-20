resource "google_service_account" "app" {
  account_id   = var.app_sa_name
  display_name = "Agentic SRE Application Service Account"
  project      = var.gcp_project
}
