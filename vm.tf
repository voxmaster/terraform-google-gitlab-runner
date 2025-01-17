# Retrieve default service account for this project
data "google_compute_default_service_account" "default" {}
# Generate a random numbers that is intended to be used as unique identifiers for other resources
resource "random_id" "instance_id" {
  byte_length = 4
}

# Create GitLab-manager VM:
resource "google_compute_instance" "gitlab_manager" {
  depends_on = [
    google_compute_router_nat.main,
  ]
  name = "${var.gcp_gitlab_resource_prefix}-manager-${random_id.instance_id.hex}"
  machine_type = var.gitlab_docker_machine_type
  zone = var.gcp_zone
  hostname = "${var.gcp_gitlab_resource_prefix}.manager"
  tags = [var.gcp_gitlab_resource_prefix]
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }
  network_interface {
    network = var.create_network ? google_compute_network.main[0].name : var.network
    subnetwork = var.create_network ? google_compute_subnetwork.main_subnet_0[0].name : var.subnetwork
  }
  metadata = {
    # enable Block Project-wide SSH keys:
    block-project-ssh-keys = "true"
    shutdown-script = <<EOT
#!/bin/bash
echo "DEREGISTER RUNNERS..."
for t in $(sudo sed -n 's/.*token = .*\(\".*\"\).*/\1/p' /etc/gitlab-runner/config.toml); 
  do curl -sS --request DELETE "${var.runners_gitlab_url}/api/v4/runners" --form "token=$t"; 
done
echo "DELETING RUNNERS..."
gcloud compute instances delete $(gcloud compute instances list --filter="labels.docker_machine=${var.gcp_gitlab_resource_prefix}-manager-${random_id.instance_id.hex}" --format="value(name)" ) --zone ${var.gcp_zone} --quiet
    EOT
  }
  labels = var.labels
  service_account {
    email  = google_service_account.sa_gitlab_manager.email
    scopes = ["cloud-platform"]
  }
  metadata_startup_script = join("\n", [data.template_file.stage1_config.rendered, local.stage2_config, data.template_file.stage3_config.rendered])
}

### 1_STAGE configuring: ###

# Take the sum of all values of "var.gitlab_register_runner.runner_limit"
locals {
  sum_concurrency = length(flatten([for i in var.gitlab_register_runner: range(i["runner_limit"])]))
}

# set up GoogleSA json key for ability of GitLab runners to work with cache
# configure the header of config.toml file
# Install gitlab-runner and docker-machine which is the fork of GitLab: https://gitlab.com/gitlab-org/ci-cd/docker-machine
data "template_file" "stage1_config" {
  template = <<EOF
#!/bin/bash
echo Waiting 30s for network...
sleep 30
echo Start
mkdir /etc/gitlab-runner/
cat >/etc/gitlab-runner/${var.gcp_gitlab_resource_prefix}-cache.json <<EOT1
${base64decode(google_service_account_key.sa_gitlab.private_key)}
EOT1
cat >/etc/gitlab-runner/config.toml <<EOT2
concurrent = ${local.sum_concurrency}
check_interval = 0
[session_server]
session_timeout = 3600
EOT2
sudo curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
sudo apt-get install gitlab-runner
sudo curl -O https://gitlab-docker-machine-downloads.s3.amazonaws.com/${var.gitlab_docker_machine_release}/docker-machine-Linux-x86_64
sudo cp docker-machine-Linux-x86_64 /usr/local/bin/docker-machine
sudo chmod +x /usr/local/bin/docker-machine
EOF
}

### STAGE_2 configuring: ###
# This locals allow us to convert "var.gitlab_register_runner" into flattened sequence and iterate through it via for_each
locals {
  register_runner_flatten = flatten([
    for key, value in var.gitlab_register_runner : [
      for index in range(1) : {
        runner_name                = key
        runner_limit               = value.runner_limit
        runner_request_concurrency = value.runner_request_concurrency
        runner_url                 = var.runners_gitlab_url
        runner_idle_nodes          = value.runner_idle_nodes
        runner_idle_time           = value.runner_idle_time
        runner_max_builds          = value.runner_max_builds
        runner_machine_type        = value.runner_machine_type
        runner_preemptible         = value.runner_preemptible
        runner_disk_size           = value.runner_disk_size
        runner_description         = value.runner_description
        runner_tag                 = value.runner_tag
      }
    ]
  ])
  runner_labels = merge(var.labels, {"docker_machine" = "${var.gcp_gitlab_resource_prefix}-manager-${random_id.instance_id.hex}"} )
}


# The docker_auth_config local variable aimed to fill in the DOCKER_AUTH_CONFIG to allow GitLab Runners be able to communicate with GCR
locals {
  docker_auth_config = {
    auths = {
      "gcr.io" = {
        auth = base64encode("_json_key:${base64decode(google_service_account_key.sa_gitlab.private_key)}")
      },
      "us.gcr.io" = {
        auth = base64encode("_json_key:${base64decode(google_service_account_key.sa_gitlab.private_key)}")
      },
      "eu.gcr.io" = {
        auth = base64encode("_json_key:${base64decode(google_service_account_key.sa_gitlab.private_key)}")
      },
      "asia.gcr.io" = {
        auth = base64encode("_json_key:${base64decode(google_service_account_key.sa_gitlab.private_key)}")
      }
    }
  }
}

# NOTE: machine options: https://gitlab.com/gitlab-org/ci-cd/docker-machine/-/blob/main/drivers/google/google.go#L95
data "template_file" "stage2_config" {
  for_each = {
    # Generate a unique string identifier for each instance
    for inst in local.register_runner_flatten : inst.runner_name => inst
  }  
  template = <<EOF
  # Register runner:
  sudo gitlab-runner register \
  --non-interactive \
  --limit ${each.value.runner_limit} \
  --request-concurrency ${each.value.runner_request_concurrency} \
  --output-limit 100000 \
  --url "${each.value.runner_url}" \
  --registration-token ${var.gitlab_registration_token} \
  --run-untagged=true \
  --executor "docker+machine" \
  --docker-image alpine:latest \
  --env "DOCKER_TLS_CERTDIR=" \
  --env "DOCKER_DRIVER=overlay2" \
  --env "DOCKER_AUTH_CONFIG=${replace(jsonencode(local.docker_auth_config),"\"","\\\"")}" \
  --cache-type gcs \
  --cache-shared=false \
  --cache-path gitlab_runners \
  --cache-gcs-credentials-file "/etc/gitlab-runner/${var.gcp_gitlab_resource_prefix}-cache.json" \
  --cache-gcs-bucket-name "${google_storage_bucket.bucket_cache.name}" \
  --docker-privileged=true \
  --docker-oom-kill-disable=false \
  --docker-disable-cache=true \
  --docker-shm-size 0 \
  --docker-disable-entrypoint-overwrite=false \
  --machine-idle-nodes ${each.value.runner_idle_nodes} \
  --machine-idle-time ${each.value.runner_idle_time} \
  --machine-max-builds ${each.value.runner_max_builds} \
  --machine-machine-driver google \
  --machine-machine-name ${each.key}-%s \
  --machine-machine-options "engine-registry-mirror=https://mirror.gcr.io" \
  --machine-machine-options "google-service-account=${google_service_account.sa_gitlab.email}" \
  --machine-machine-options "google-zone=${var.gcp_zone}" \
  --machine-machine-options "google-metadata=block-project-ssh-keys=true" \
  --machine-machine-options "google-machine-image=ubuntu-os-cloud/global/images/family/ubuntu-1804-lts" \
  --machine-machine-options "google-project=${var.gcp_project_id}" \
  --machine-machine-options "google-network=${var.create_network ? google_compute_network.main[0].name : var.network}" \
  --machine-machine-options "google-subnetwork=${var.create_network ? google_compute_network.main[0].name : var.subnetwork}" \
  ${each.value.runner_preemptible == true ? "--machine-machine-options \"google-preemptible\"" : ""} \
  --machine-machine-options "google-use-internal-ip-only=true" \
  --machine-machine-options "google-machine-type=${each.value.runner_machine_type}" \
  --machine-machine-options "google-disk-size=${each.value.runner_disk_size}" \
  --machine-machine-options "google-disk-type=pd-balanced" \
  --machine-machine-options "google-tags=${var.gcp_gitlab_resource_prefix}" \
  --description "${each.value.runner_description}" \
  --tag-list "${each.value.runner_tag}" \
  ${join(" ", [for k, v in local.runner_labels : "--machine-machine-options \"google-label=${k}:${v}\""])} \

  EOF
}

locals {
  stage2_config = join("\n", [for b in data.template_file.stage2_config: b.rendered])
}
data "template_file" "stage3_config" {
  template = <<EOF
  sudo gitlab-runner start
  # Next command force the creation of a new self-signed CA for docker-machine and require because of I got next error:
  ### Error creating machine: Error checking the host: Error checking and/or regenerating the certs: 
  ### There was an error validating certificates for host "x.x.x.x:2376": remote error: tls: bad certificate
  sudo rm -rf /root/.docker/machine/certs/*
  sudo gitlab-runner restart
  sudo gitlab-runner verify
  EOF
}
