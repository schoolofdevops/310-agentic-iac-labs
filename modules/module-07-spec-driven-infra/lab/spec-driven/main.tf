variable "bucket_name" {
  description = "Name for the build artifacts bucket (FR-005: variable, not hardcoded)"
  type        = string
  default     = "m07-build-artifacts-demo"
}

resource "aws_s3_bucket" "artifacts" {
  bucket = var.bucket_name

  tags = {
    purpose    = "build-artifacts" # FR-004
    managed_by = "terraform"       # FR-004
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled" # FR-001 / SC-001
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true # FR-002 / SC-002
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # FR-003 / SC-003
    }
  }
}
