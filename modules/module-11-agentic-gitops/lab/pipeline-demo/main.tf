terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "webhook_token" {
  description = "Token for the pipeline's status webhook"
  type        = string
  default     = "AKIAABCDEFGHIJKLMNOP"
}

resource "local_file" "pipeline_config" {
  filename = "${path.module}/rendered/pipeline.env"
  content  = "WEBHOOK_TOKEN=${var.webhook_token}\n"
}
