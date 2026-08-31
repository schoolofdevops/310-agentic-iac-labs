terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

variable "site_dir" {
  description = "Path to local dir with static HTML you author/edit"
  type        = string
  default     = "./site"
}

resource "docker_image" "nginx" {
  name         = "nginx:1.27-alpine"
  keep_locally = true
}

resource "docker_container" "nginx" {
  name  = "local-nginx-test"
  image = docker_image.nginx.image_id

  # bind-mount local dir -> nginx serves exactly what's on disk, diffable in git
  volumes {
    host_path      = var.site_dir
    container_path = "/usr/share/nginx/html"
    read_only      = true
  }

  ports {
    internal = 80
    external = 8080
    ip       = "127.0.0.1" # localhost only, no external exposure
  }

  # no env vars / secrets passed
  restart = "no"
}

output "url" {
  value = "http://127.0.0.1:8080"
}
