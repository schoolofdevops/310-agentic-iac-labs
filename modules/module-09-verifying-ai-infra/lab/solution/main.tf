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

# checkov's CKV2_AWS_62 / CKV2_AWS_61 / CKV_AWS_144 findings on both buckets below are a
# deliberate, reviewed exception. Event notifications, lifecycle, and cross-region
# replication are production DR concerns, not a lab requirement. That exception is passed
# to checkov via --skip-check on the CLI in pipeline.sh, not an inline comment: inline
# #checkov:skip comments did not actually suppress these findings when tested against
# checkov 3.3.16 in this course's own environment, the CLI flag did. Trivy's inline ignore
# comment did work, see the aws_s3_bucket_server_side_encryption_configuration resources
# further down, where AWS-0132 actually reports.
resource "aws_s3_bucket" "reports" {
  bucket        = "m09-lab-reports"
  force_destroy = true

  tags = {
    Environment = "lab"
    Owner       = "m09-lab"
    ManagedBy   = "terraform"
  }
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

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AWS-0132:a customer-managed KMS key is a real production hardening step this lab's SSE-KMS default already covers well enough
resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

#trivy:ignore:AWS-0132:a customer-managed KMS key is a real production hardening step this lab's SSE-KMS default already covers well enough
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "reports" {
  bucket        = aws_s3_bucket.reports.id
  target_bucket = aws_s3_bucket.backups.id
  target_prefix = "logs/reports/"
}

resource "aws_s3_bucket_logging" "backups" {
  bucket        = aws_s3_bucket.backups.id
  target_bucket = aws_s3_bucket.backups.id
  target_prefix = "logs/backups/"
}
