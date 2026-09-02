resource "aws_s3_bucket" "reports" {
  bucket = "m09-eval-reports"

  tags = {
    Environment = "lab"
    Owner       = "m09-lab"
    ManagedBy   = "terraform-module-conventions-skill"
  }
}

resource "aws_s3_bucket" "backups" {
  bucket = "m09-eval-backups"

  tags = {
    Environment = "lab"
    Owner       = "m09-lab"
    ManagedBy   = "terraform-module-conventions-skill"
  }
}
