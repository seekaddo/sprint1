variable "exoscale_key" { type = string  }
variable "exoscale_secret" { type = string }

terraform {
  required_providers {
    exoscale = {
      source = "terraform-providers/exoscale"
    }
  }
}

provider "exoscale" {
  key = var.exoscale_key
  secret = var.exoscale_secret
}

locals {
  zone = "at-vie-1"
  # instnace in Vienna for low latency
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}

output "vm_list" {
  value = exoscale_instance_pool.sprintWeb.virtual_machines
  description = "The list of Instance Pool members (Compute instance names)."
}

# Data section
data "exoscale_compute_template" "sprintWeb" {
  zone = local.zone
  name = "Linux Ubuntu 18.04 LTS 64-bit"
}

# Rescource section
resource "exoscale_instance_pool" "sprintWeb" {
  name               = "FH-CC Sprint 1"
  description        = "Instnace pool for the sprint 1 task"
  template_id        = data.exoscale_compute_template.sprintWeb.id
  service_offering   = "micro"
  size               = 2
  disk_size          = 10
  zone               = local.zone
  security_group_ids = [exoscale_security_group.exSecg.id]
  user_data          = <<EOF
#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

# region Install Docker
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

apt-key fingerprint 0EBFCD88
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
# endregion

# region Launch containers

# Run the load generator
docker run -d \
  --restart=always \
  -p 80:8080 \
  janoszen/http-load-generator:1.0.1
EOF

}

resource "exoscale_security_group" "exSecg" {
  name = "SprintWebSec"
}

resource "exoscale_security_group_rule" "http" {
  security_group_id = exoscale_security_group.exSecg.id
  type              = "INGRESS"
  protocol          = "tcp"
  cidr              = "0.0.0.0/0"
  start_port        = 80
  end_port          = 80
}


resource "exoscale_nlb" "sprintWeb" {
  name        = "website-nlb"
  description = "A simple NLB service"
  zone        = local.zone
}

resource "exoscale_nlb_service" "sprintWeb" {
  zone             = exoscale_nlb.sprintWeb.zone
  name             = "NLB-web"
  description      = "Website over HTTP"
  nlb_id           = exoscale_nlb.sprintWeb.id
  instance_pool_id = exoscale_instance_pool.sprintWeb.id
  protocol         = "tcp"
  port             = 80
  target_port      = 80
  strategy         = "round-robin"

  healthcheck {
    port     = 80
    mode     = "http"
    uri      = "/health"
    interval = 10
    timeout  = 10
    retries  = 1
  }
}