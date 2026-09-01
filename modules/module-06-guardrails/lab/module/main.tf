resource "aws_s3_bucket" "artifacts" {
  bucket = "m06-lab-artifacts"

  tags = {
    Environment = "lab"
    Owner       = "m06-lab"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket        = "m06-lab-logs"
  force_destroy = true

  tags = {
    Environment = "lab"
    Owner       = "m06-lab"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "docs" {
  bucket = "m06-lab-docs"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}
