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
    s3       = var.endpoint
    dynamodb = var.endpoint
  }
}

variable "config_api_key" {
  description = "API key the app uses to read its own config table. Set via TF_VAR_config_api_key, never a default."
  type        = string
  sensitive   = true
}

locals {
  tags = {
    Environment = "dev"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "uploads" {
  bucket = "capstone-app-uploads"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "config" {
  name         = "capstone-app-config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "environment"

  attribute {
    name = "environment"
    type = "S"
  }

  tags = local.tags
}
