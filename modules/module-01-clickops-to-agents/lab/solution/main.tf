## Lab 1: Getting Started with Agentic IaC, solution
## Same intent as starter/main.tf. The fix: the key is no longer typed into the
## module. It is supplied at apply time from the environment and never touches disk
## in plaintext inside the repo.

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

variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships nginx access logs to S3. Set via TF_VAR_log_shipper_key, never a default."
  type        = string
  sensitive   = true
}

resource "local_file" "index_html" {
  filename = "${path.module}/rendered/index.html"
  content  = "<html><body><h1>Module 01 lab</h1></body></html>"
}

resource "local_file" "log_shipper_env" {
  filename        = "${path.module}/rendered/log-shipper.env"
  content         = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
  file_permission = "0600"
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
