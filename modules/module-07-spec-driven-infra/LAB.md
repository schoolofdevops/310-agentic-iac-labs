# Lab 7: Write a Spec, Generate Against It, Check the Criteria

**Tier 1** · ~20 min · Terraform, Checkov, and Floci, same setup as the last few labs.

M01's lab gave you a one-line intent and a starter skeleton. That's fine for a first exercise.
Real work rarely comes in one line, it comes as a ticket that says roughly what someone wants and
leaves the rest for you to fill in. This lab gives you exactly that kind of ticket, and you're
going to answer it two different ways: once with a written spec, once by feel. Then you check both
against the same criteria and see what the difference actually buys you.

## Pre Requisites

- The Docker socket reachable at `/var/run/docker.sock`, same as every Tier 1 lab so far.
- `terraform` and `checkov` on your `PATH`.

## The ticket

Here it is, verbatim, the way it would land in your queue:

> Give me an S3 bucket for storing build artifacts.

Read it again. It says nothing about who can read the bucket, whether an overwritten artifact is
recoverable, or whether it's encrypted. That silence is normal. Most tickets look exactly like
this.

## Write the spec

You could start typing Terraform right now. Don't. **Write** a spec first: what this bucket must
do, what it must never do, and how you'll know it's right, before any HCL exists.

GitHub's Spec Kit gives you a real, structured template for this (`specify init` installs it as
skills inside Claude Code: `/speckit-specify`, `/speckit-plan`, `/speckit-tasks`). This lab's own
spec was written straight into that template's shape, filled in by hand:

`file: lab/spec-driven/spec.md`
```
# Feature Specification: Build Artifacts Bucket

## Requirements

### Functional Requirements

- FR-001: The bucket MUST have versioning enabled.
- FR-002: The bucket MUST have all four public-access-block settings enabled.
- FR-003: The bucket MUST use server-side encryption (SSE) by default.
- FR-004: The bucket MUST be tagged with purpose and managed_by.
- FR-005: The bucket name MUST be a variable, not hardcoded.

### Constraints

- C-001: The bucket MUST NOT have a public bucket policy attached.
- C-002: No account-specific value may be hardcoded into a resource block.

## Success Criteria

- SC-001: versioning status = Enabled
- SC-002: all four public-access-block settings = true
- SC-003: server-side encryption configured, AES256 or aws:kms
- SC-004: tags include purpose and managed_by
- SC-005: checkov passes the specific checks this spec maps to (CKV_AWS_21,
  CKV2_AWS_6, CKV_AWS_19) -- see the note below
```

Three things separate this from the one-line ticket: **requirements** (what it must do),
**constraints** (what it must never do), and **acceptance criteria** (how you'll check, stated
before you generate anything). The full spec is in `lab/spec-driven/spec.md`, read it end to end,
it's short.

Notice SC-005 doesn't promise a fully clean `checkov` run. Keep that in mind, you'll see exactly
why in a few steps.

## Generate against the spec

**Write** the module so every line traces back to a requirement:

`file: lab/spec-driven/main.tf`
```
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
```

**Validate** it the usual way:

```
cd lab/spec-driven
terraform fmt -check -diff .
terraform init -backend=false
terraform validate
```

`[ Expected output ]`
```
Success! The configuration is valid.
```

## Try the same ticket by feel

Now open a second directory and answer the exact same ticket, no spec, no requirements list, just
the one line. Don't think about it too hard, that's the point:

`file: lab/vibe-coded/main.tf`
```
resource "aws_s3_bucket" "artifacts" {
  bucket = "m07-build-artifacts-demo-vibe"
}
```

That's a real, honest first pass at "give me a bucket for build artifacts." It's not a strawman,
it's what you get when you stop at the first thing that satisfies the sentence.

## Run checkov against both

```
checkov -d lab/spec-driven --compact --quiet
```

`[ Expected output ]`
```
Passed checks: 11, Failed checks: 5, Skipped checks: 0
```

```
checkov -d lab/vibe-coded --compact --quiet
```

`[ Expected output ]`
```
Passed checks: 5, Failed checks: 7, Skipped checks: 0
```

Read both finding lists (`lab/evidence/checkov-spec-driven.txt` and
`checkov-vibe-coded.txt` have the full real output). The vibe-coded version fails on
`CKV_AWS_21` (no versioning), `CKV2_AWS_6` (no public access block), and `CKV_AWS_145`, exactly
the things FR-001 through FR-003 named up front. The spec-driven version passes every check that
traces back to one of its own requirements.

**Observe** something else, though: the spec-driven version still has 5 failed checks. `checkov`
also flags event notifications, a lifecycle configuration, access logging, cross-region
replication, and KMS-specifically-required encryption, none of which this spec's author (you) put
in the requirements list. **Why?** Because a spec's acceptance criteria only cover what someone
thought to write down. That's not a flaw in spec-driven work, it's exactly why the policy gate in
M09 still runs after this. A spec shapes what gets generated. It doesn't replace the check that
runs afterward.

## Apply both, for real, and see what nothing stops

Start Floci the usual way:

```
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0
```

**Apply** the spec-driven module and check the real state against SC-001 through SC-004:

```
cd lab/spec-driven
terraform apply -auto-approve
terraform state show aws_s3_bucket_versioning.artifacts
terraform state show aws_s3_bucket_public_access_block.artifacts
```

`[ Expected output ]`
```
    versioning_configuration {
        status     = "Enabled"
    }
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
```

Now **apply** the vibe-coded one too:

```
cd ../vibe-coded
terraform apply -auto-approve
```

`[ Expected output ]`
```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Read that again. Nothing stopped it. No gate, no policy check, ran between "by feel" and a real
bucket existing with no versioning, no public-access-block, and no encryption. `apply` doesn't
care whether you wrote a spec. Only a downstream check does, which is exactly M06 and M09's job,
not this module's.

**Destroy** both before you're done, there's nothing here worth leaving up:

```
terraform destroy -auto-approve
cd ../spec-driven
terraform destroy -auto-approve
docker rm -f floci
```

`[ Expected output ]`
```
Destroy complete! Resources: 4 destroyed.
```

#### Exercise

Write your own spec for a real, underspecified ask from your own backlog: requirements,
constraints, and acceptance criteria, before you generate anything. Then generate against it and
check the output line by line against your own acceptance criteria, not by eyeballing it.

#### Summary

You wrote a real spec, generated a module that traces every line back to a requirement, and
compared it against the same ticket answered by feel. The spec-driven version passed every check
tied to its own requirements. The vibe-coded version failed seven, and nothing stopped either one
from applying. A spec makes the proposal better. It's still the pipeline, the gate in M06 and the
policy check in M09, that decides whether `apply` was ever safe to run. You'll need that spec
habit again in the capstone, where nobody hands you a one-line ticket at all.

##### Reading List

- [GitHub Spec Kit](https://github.com/github/spec-kit)
- [Checkov S3 policies](https://www.checkov.io/5.Policy%20Index/terraform.html)
- `reading/concepts.md` in this module: why vibe coding specifically fails on infrastructure, not
  just why it's messy

##### Search Keywords

- spec-driven development, Spec Kit, Kiro specs
- requirements, constraints, acceptance criteria
- vibe coding
- checkov, S3 bucket policies, public access block
