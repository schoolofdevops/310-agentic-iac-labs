terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships access logs to S3. Set via TF_VAR_log_shipper_key, never a default."
  type        = string
  sensitive   = true
}

resource "local_file" "log_shipper_env" {
  filename        = "${path.module}/rendered/log-shipper.env"
  content         = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
  file_permission = "0600"
}
