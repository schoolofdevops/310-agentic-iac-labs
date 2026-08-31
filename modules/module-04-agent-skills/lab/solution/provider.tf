# Tier-1 provider stub, copied from labs/shared/floci-spike/provider.tf.
# Run 2: terraform-module-conventions skill available, provider pin applied
# per the skill's "Provider pins" rule.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
variable "endpoint" {
  type    = string
  default = "http://localhost:4566"
}
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
  s3_use_path_style           = true
  endpoints {
    s3 = var.endpoint
  }
}
