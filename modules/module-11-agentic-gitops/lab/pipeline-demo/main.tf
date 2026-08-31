terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "webhook_token" {
  description = "Token for the pipeline's status webhook. Set via TF_VAR_webhook_token, never a default."
  type        = string
  sensitive   = true
}

resource "local_file" "pipeline_config" {
  filename = "${path.module}/rendered/pipeline.env"
  content  = "WEBHOOK_TOKEN=${var.webhook_token}\n"
}
