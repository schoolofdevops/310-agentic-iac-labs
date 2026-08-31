## Lab 3: Context Engineering for Infrastructure
## Run 2: the same one-line intent, same repo, AGENTS.md present this time.

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
  content  = "<html><body><h1>Module 03 lab</h1></body></html>"
}

resource "local_file" "log_shipper_env" {
  filename = "${path.module}/rendered/log-shipper.env"
  content  = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
}

resource "docker_image" "nginx" {
  name = "nginx:1.27-alpine"
}

resource "docker_container" "site" {
  name  = "m03-lab-site"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 8081
  }

  volumes {
    host_path      = abspath(local_file.index_html.filename)
    container_path = "/usr/share/nginx/html/index.html"
    read_only      = true
  }
}
