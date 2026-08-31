terraform {
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
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    s3 = var.endpoint
  }
}

variable "endpoint" {
  type    = string
  default = "http://localhost:4566"
}

resource "aws_s3_bucket" "reports" {
  bucket        = "m09-lab-reports"
  force_destroy = true
}

resource "aws_s3_bucket" "backups" {
  bucket        = "m09-lab-backups"
  force_destroy = true

  tags = {
    Environment = "lab"
    Owner       = "m09-lab"
    ManagedBy   = "terraform"
  }
}
