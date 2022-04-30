###* Service Account for Gitlab Manager Instance *###
resource "google_service_account" "sa_gitlab_manager" {
  project      = var.gcp_project_id
  account_id   = "sa-${var.gcp_gitlab_resource_prefix}-manager"
  display_name = "sa-${var.gcp_gitlab_resource_prefix}-manager"
  description  = "SA for Gitlab Manager Instance"
}
resource "google_project_iam_member" "sa_gitlab_manager" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",
    "roles/iam.serviceAccountUser"
  ])
  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.sa_gitlab_manager.email}"
}

###* Service Account for Runners to use Cache Bucket and Read from Container/Artifact Registry *###
resource "google_service_account" "sa_gitlab" {
  project     = var.gcp_project_id
  account_id = "sa-${var.gcp_gitlab_resource_prefix}"
  display_name = "sa-${var.gcp_gitlab_resource_prefix}"
  description = "SA for Gitlab Runner cache and GCR ReadOnly access (Pull Container Images)"
}

resource "google_service_account_key" "sa_gitlab" {
  service_account_id = google_service_account.sa_gitlab.name
}

resource "google_storage_bucket_iam_binding" "gitlab_runner" {
  bucket = google_storage_bucket.bucket_cache.name
  role   = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.sa_gitlab.email}",
  ]
}

resource "google_project_iam_member" "sa_gitlab" {
  project     = var.gcp_project_id
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.sa_gitlab.email}"

  condition {
    title       = "GCR Only Access"
    description = "Limits access to Cloud Container Registry only. Managed by Terraform."
    expression  = join( " || ",
      [
      "resource.name.startsWith(\"projects/_/buckets/artifacts.${var.gcp_project_id}.appspot.com\")", 
      "resource.name.startsWith(\"projects/_/buckets/us.artifacts.${var.gcp_project_id}.appspot.com\")",
      "resource.name.startsWith(\"projects/_/buckets/eu.artifacts.${var.gcp_project_id}.appspot.com\")",
      "resource.name.startsWith(\"projects/_/buckets/asia.artifacts.${var.gcp_project_id}.appspot.com\")"
      ]
    )
  }
}

resource "google_project_iam_member" "sa_gitlab_artifacts" {
  project     = var.gcp_project_id
  role   = "roles/artifactregistry.reader"
  member = "serviceAccount:${google_service_account.sa_gitlab.email}"
}
