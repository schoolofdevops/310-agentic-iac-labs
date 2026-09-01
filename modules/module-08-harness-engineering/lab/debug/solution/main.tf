# Lab 8 debugging exercise -- fixed. The root cause was never the version or
# the cache, it was the argument itself: `endpoint_url` is not a real
# AWS-provider argument. The real shape is the `endpoints {}` block, the same
# stub every Tier-1 lab in this course uses (labs/shared/floci-spike/provider.tf).
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
  endpoints {
    s3 = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "m08-debug-artifacts"
}
