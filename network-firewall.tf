
resource "google_compute_firewall" "allow_internal_ssh" {
  count = var.create_firewall_rules ? 1 : 0
  name = "${var.create_network ? google_compute_network.main[0].name : var.network}-allow-internal-ssh"
  network = var.create_network ? google_compute_network.main[0].name : var.network
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = var.create_network ? [google_compute_subnetwork.main_subnet_0[0].ip_cidr_range, "35.235.240.0/20"] : null
  source_tags = var.create_network ? null : [var.gcp_gitlab_resource_prefix]
  target_tags = [var.gcp_gitlab_resource_prefix]
  description = "Allow SSH access inside VPC for Runners and IAP for TCP forwarding if created with runner TF module. Managed by Terraform"
}

resource "google_compute_firewall" "allow_internal_docker" {
  count = var.create_firewall_rules ? 1 : 0
  name = "${var.create_network ? google_compute_network.main[0].name : var.network}-allow-internal-docker"
  network = var.create_network ? google_compute_network.main[0].name : var.network
  allow {
    protocol = "tcp"
    ports    = ["2376"]
  }
  source_tags = [var.gcp_gitlab_resource_prefix]
  target_tags = [var.gcp_gitlab_resource_prefix]
  description = "Allow docker connection. Managed by Terraform"
}

resource "google_compute_firewall" "dm_firewall_rule_fix" {
  count   = var.dm_firewall_rule_fix ? 1 : 0
  name    = "docker-machines"
  network = var.create_network ? google_compute_network.main[0].name : var.network
  allow {
    protocol = "tcp"
    ports    = ["2376"]
  }
  disabled  = true
  priority  = 65535
  source_tags = ["gitlab-runner-fix"]
  target_tags = ["gitlab-runner-fix"]
  description = "This rule is a workaround for the docker-machine issue https://gitlab.com/gitlab-org/ci-cd/docker-machine/-/issues/47.  Managed by Terraform"
}
