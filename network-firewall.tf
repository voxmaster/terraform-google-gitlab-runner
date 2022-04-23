
resource "google_compute_firewall" "allow-ssh" {
  count = var.create_firewall_rules ? 1 : 0
  name = "${google_compute_network.main[0].name}-allow-internal-workers-ssh"
  network = google_compute_network.main[0].name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = [google_compute_subnetwork.main_subnet_0[0].ip_cidr_range, "35.235.240.0/20"]
  target_tags = [var.gcp_gitlab_resource_prefix]
  description = "Allow ssh access inside VPC for all spinned up workers and + IAP for TCP forwarding. Managed by terraform"
}

resource "google_compute_firewall" "allow-all-internal" {
  count = var.create_firewall_rules ? 1 : 0
  name = "${google_compute_network.main[0].name}-docker-machines"
  network = google_compute_network.main[0].name
  allow {
    protocol = "tcp"
    ports    = ["2376"]
  }
  source_ranges = [google_compute_subnetwork.main_subnet_0[0].ip_cidr_range]
  target_tags = ["docker-machine"]
  description = "Allow encrypted communication with the docker daemon to all VMs with docker-machine tag. Managed by terraform"
}

resource "google_compute_firewall" "dm_firewall_rule_fix" {
  count   = var.dm_firewall_rule_fix ? 1 : 0
  name    = "docker-machines"
  network = google_compute_network.main[0].name
  allow {
    protocol = "tcp"
    ports    = ["2376"]
  }
  direction = "EGRESS"
  disabled  = true
  priority  = 65535
  source_ranges = [google_compute_subnetwork.main_subnet_0[0].ip_cidr_range]
  target_tags   = ["dummy"]
  description   = "This rule is a workaround for the docker-machine issue https://gitlab.com/gitlab-org/ci-cd/docker-machine/-/issues/47. Managed by terrafrom"
}
