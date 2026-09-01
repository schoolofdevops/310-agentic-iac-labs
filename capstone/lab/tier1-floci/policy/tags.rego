package main

import rego.v1

# Every aws_s3_bucket / aws_dynamodb_table must carry Environment, Owner, and
# ManagedBy tags. Neither Trivy nor Checkov's built-in rule sets encode this,
# it is this repo's own convention.

required_tags := {"Environment", "Owner", "ManagedBy"}

taggable_types := {"aws_s3_bucket", "aws_dynamodb_table"}

deny contains msg if {
	some rc in input.resource_changes
	taggable_types[rc.type]
	tags := object.get(rc.change.after, "tags", {})
	present := {k | some k, _ in tags}
	missing := required_tags - present
	count(missing) > 0
	msg := sprintf("%s is missing required tag(s): %v", [rc.address, missing])
}
