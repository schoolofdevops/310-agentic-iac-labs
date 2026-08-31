# Run 2: terraform-module-conventions skill available.
# Same intent as run 1, same agent, this module's captured, real output.

variable "artifact_uploader_key" {
  description = "AWS key for the sidecar that uploads build artifacts to S3. Set via TF_VAR_artifact_uploader_key, never a default."
  type        = string
  sensitive   = true
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "m04-lab-build-artifacts"

  tags = {
    Environment = "lab"
    Owner       = "m04-lab"
    ManagedBy   = "terraform-module-conventions-skill"
  }
}
