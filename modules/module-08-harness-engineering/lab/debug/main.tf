# Lab 8 debugging exercise -- broken. Uses the argument name Floci's own
# README shows (`endpoint_url`), which is not real AWS-provider syntax. This
# is a genuine, reproducible mistake, not a staged typo.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
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

  endpoint_url = "http://localhost:4566"
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "m08-debug-artifacts"
}
