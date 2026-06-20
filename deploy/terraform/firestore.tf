################################################################################
# Firestore
#
# CRITICAL: type = "FIRESTORE_NATIVE" is mandatory.
# DATASTORE_MODE does NOT support TTL policies, which are required for
# automatic 60-minute alert group cleanup.
################################################################################

resource "google_firestore_database" "agentic_sre_db" {
  name        = var.firestore_database_name
  project     = var.gcp_project
  location_id = var.gcp_region
  type        = "FIRESTORE_NATIVE"

  deletion_policy = "DELETE"
}

# TTL policy on the expires_at field of alert_groups collection.
# Firestore will automatically delete documents once expires_at is in the past.
resource "google_firestore_field" "alert_groups_ttl" {
  project    = var.gcp_project
  database   = google_firestore_database.agentic_sre_db.name
  collection = "alert_groups"
  field      = "expires_at"

  ttl_config {}

  depends_on = [google_firestore_database.agentic_sre_db]
}
