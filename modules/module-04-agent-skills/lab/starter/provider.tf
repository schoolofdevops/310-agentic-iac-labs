# Tier-1 provider stub, copied from labs/shared/floci-spike/provider.tf.
# NOTE: this is run 1, no skill available yet, so the version constraint below
# is left off on purpose, this is what "no convention written down" looks like.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source = "hashicorp/aws"
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
