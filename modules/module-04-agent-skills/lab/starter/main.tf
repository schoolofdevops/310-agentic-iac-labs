# Run 1: no terraform-module-conventions skill available.
# This module's captured, real output against the intent:
# "Give me a small S3 bucket for build artifacts, with a credential for the
# uploader sidecar that ships them there."

variable "artifact_uploader_key" {
  description = "AWS key for the sidecar that uploads build artifacts to S3"
  type        = string
  default     = "AKIAQRSTUVWXYZ012345"
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "m04-lab-build-artifacts"
}
