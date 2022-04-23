# create VPC
resource "google_compute_network" "main" {
  count = var.create_network ? 1 : 0
  name                    = var.gcp_gitlab_resource_prefix
  auto_create_subnetworks = "false"
  routing_mode            = "GLOBAL"
}
# create subnet
resource "google_compute_subnetwork" "main_subnet_0" {
  count = var.create_network ? 1 : 0
  name                     = "${google_compute_network.main[0].name}-subnet-0"
  private_ip_google_access = true
  ip_cidr_range            = var.gcp_main_vpc_sub_ip_range
  network = google_compute_network.main[0].name
  region  = var.gcp_region
}

resource "google_compute_router" "main" {
  count = var.create_network ? 1 : 0
  name    = "${google_compute_network.main[0].name}-router-0"
  network = google_compute_network.main[0].name
  region  = var.gcp_region
}

resource "google_compute_address" "main" {
  count = var.create_network ? 1 : 0
  name         = "${google_compute_router.main[0].name}-ip-0"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  region       = var.gcp_region
}

resource "google_compute_router_nat" "main" {
  count = var.create_network ? 1 : 0
  name                               = "${google_compute_router.main[0].name}-nat-0"
  router                             = google_compute_router.main[0].name
  region  = var.gcp_region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  nat_ips                            = [google_compute_address.main[0].self_link]
  log_config {
    enable = false
    filter = "ALL"
  }
}

