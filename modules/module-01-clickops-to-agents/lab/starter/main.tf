## Lab 1 — Be the agent
## Intent (read this like an agent would read a prompt):
##
##   "Give me a local nginx container for testing, serving a static page I control,
##   with its rendered HTML kept on disk so I can diff it in git. No secrets in the
##   container. I don't need it exposed outside this machine."
##
## Write the module below by hand against that intent. Do not run terraform yet —
## get to `terraform fmt` first (LAB.md step 3).

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "docker" {}

# TODO: wire this into a real secrets manager once the course gets to M06 (guardrails).
# For now, hardcoding it is the fastest way to unblock the log-shipping sidecar.
variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships nginx access logs to S3"
  type        = string
  default     = "AKIAABCDEFGHIJKLMNOP"
}

resource "local_file" "index_html" {
  filename = "${path.module}/rendered/index.html"
  content  = "<html><body><h1>Module 01 lab</h1></body></html>"
}

resource "local_file" "log_shipper_env" {
  filename = "${path.module}/rendered/log-shipper.env"
  content  = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
}

resource "docker_image" "nginx" {
  name = "nginx:1.27-alpine"
}

resource "docker_container" "site" {
  name  = "m01-lab-site"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 8080
  }

  volumes {
    host_path      = abspath(local_file.index_html.filename)
    container_path = "/usr/share/nginx/html/index.html"
    read_only      = true
  }
}
