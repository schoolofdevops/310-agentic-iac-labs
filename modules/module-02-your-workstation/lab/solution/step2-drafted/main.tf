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

variable "container_name" {
  description = "Name of the local nginx test container"
  type        = string
  default     = "nginx-local-test"
}

variable "host_port" {
  description = "Port on localhost to bind nginx to (loopback only, not exposed externally)"
  type        = number
  default     = 8080
}

# Static page content lives here on disk, tracked in git, so changes are diffable.
resource "local_file" "index_html" {
  filename = "${path.module}/html/index.html"
  content  = <<-EOT
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>Local nginx test page</title>
    </head>
    <body>
      <h1>Hello from local nginx</h1>
      <p>Edit html/index.html and re-apply to change this page.</p>
    </body>
    </html>
  EOT
}

resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = true
}

resource "docker_container" "nginx" {
  name  = var.container_name
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = var.host_port
    ip       = "127.0.0.1" # loopback only, not reachable from outside this machine
  }

  volumes {
    host_path      = local_file.index_html.filename
    container_path = "/usr/share/nginx/html/index.html"
    read_only      = true
  }

  # No env vars, no secrets passed to the container.
}

output "url" {
  value = "http://127.0.0.1:${var.host_port}"
}
