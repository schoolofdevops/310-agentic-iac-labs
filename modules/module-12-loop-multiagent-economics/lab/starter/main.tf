terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# TODO: wire this into a real secrets manager once the course gets to M06 (guardrails).
# For now, hardcoding it is the fastest way to unblock the log-shipping sidecar.
variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships access logs to S3"
  type        = string
  default     = "AKIAABCDEFGHIJKLMNOP"
}

resource "local_file" "log_shipper_env" {
  filename = "${path.module}/rendered/log-shipper.env"
  content  = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
}
