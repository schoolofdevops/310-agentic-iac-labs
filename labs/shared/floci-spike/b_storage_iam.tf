# B — S3 + IAM (the M04 skills-pack lab shape)
resource "aws_s3_bucket" "app" {
  bucket = "spike-app-assets-000000000000"
  tags   = { Env = "lab" }
}
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "app" {
  name               = "spike-app-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}
resource "aws_iam_role_policy" "app_s3" {
  name = "spike-app-s3"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${aws_s3_bucket.app.arn}/*"
    }]
  })
}
resource "aws_iam_instance_profile" "app" {
  name = "spike-app-profile"
  role = aws_iam_role.app.name
}
output "bucket_arn" {
  value = aws_s3_bucket.app.arn
}
output "role_arn" {
  value = aws_iam_role.app.arn
}
