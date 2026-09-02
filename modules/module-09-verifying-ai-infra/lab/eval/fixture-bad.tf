resource "aws_s3_bucket" "reports" {
  bucket = "m09-eval-reports"

  tags = {
    Environment = "lab"
  }
}

resource "aws_s3_bucket" "backups" {
  bucket = "m09-eval-backups"
}
