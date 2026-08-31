package main

import rego.v1

# Every aws_s3_bucket must carry an Owner tag. Neither Trivy nor Checkov's
# built-in rule sets encode this, it is this repo's own convention.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket"
	tags := object.get(rc.change.after, "tags", {})
	not tags.Owner
	msg := sprintf("%s has no Owner tag: every aws_s3_bucket must carry tags.Owner", [rc.address])
}
