resource "random_id" "bucket_id" {
  byte_length = 4
}
# Google GCS bucket for keeping caches from GitLab pipeline 
resource "google_storage_bucket" "bucket_cache" {
  name          = "${var.gcp_gitlab_resource_prefix}-${random_id.bucket_id.hex}"
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true
  lifecycle_rule {
    condition {
      age = var.gcp_gcs_cache_age
    }
    action {
      type = "Delete"
    }
  }
  lifecycle {
    ignore_changes = [ logging ]
  }

  labels = var.labels
}
