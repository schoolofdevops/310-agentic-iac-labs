# Project 08: Build a Verification-Before-Claiming Harness Using a Skill and a Hook

**Tier 1** · ~20 min · Docker socket mounted, `floci/floci:1.7.0` pinned, provider stub copied from
`labs/shared/floci-spike/provider.tf`, same rules as every Tier 1 lab in this course.

In this project, you will assemble a skill and a hook into one working harness that stops an
unbacked "checkov passes" claim from ever reaching you. You will then prove the harness against
three real disciplines from the superpowers pattern: verification-before-claiming, test-first
development, and root-cause debugging.

**What you're building, at a glance:**

- A skill that states the rule: no completion claim without real evidence attached
- A hook that enforces it mechanically, blocking a claim with no evidence and passing one that
  has it
- A real RED-GREEN test-first cycle against a Terraform module, the `CKV_AWS_145` encryption check
- A real bug, three real wrong fixes, then a real root cause found by comparing against a
  known-working example
- A real `terraform apply` and `destroy` at each stage, against Floci

M04 gave you a skill. M05 gave you a live MCP connection. M06 gave you a hook. This project
assembles a skill and a hook into one harness.

## Pre Requisites

- Docker reachable at `/var/run/docker.sock`. Check with `docker info`
- `terraform` and `checkov` on your `PATH`, installed per Environment Setup

## Stage 1: Assemble a verification-before-claiming harness

### Step 1: Get the starter module

```
cd modules/module-08-harness-engineering/lab
```

`file: starter/main.tf`
```
resource "aws_s3_bucket" "artifacts" {
  bucket = "m08-lab-artifacts"

  tags = {
    owner = "platform-team"
  }
}
```

### Step 2: Watch an unbacked claim slip through

**Open** Claude Code (or Codex) in this directory and give it this exact prompt:

```
claude -p "Review the S3 bucket in starter/main.tf and tell me if it's clean and ready to ship." \
  --permission-mode plan --allowedTools "Read"
```

This is what came back, captured for real, with no harness in place yet:

> "Looks good, checkov passes, the module is clean."

Nothing stopped that claim from reaching you. **Run** the real scan and check whether it was true:

```
checkov -d starter --compact --quiet
```

`[ Expected output ]`
```
Passed checks: 5, Failed checks: 7, Skipped checks: 0

Check: CKV_AWS_21: "Ensure all data stored in the S3 bucket have versioning enabled"
	FAILED for resource: aws_s3_bucket.artifacts
Check: CKV2_AWS_6: "Ensure that S3 bucket has a Public Access block"
	FAILED for resource: aws_s3_bucket.artifacts
```

Seven real failures, and the claim said "clean." Nothing mechanical stopped that gap from
reaching you. That's the failure this project fixes.

### Step 3: Write the skill that states the rule

`file: .claude/skills/verify-before-claiming/SKILL.md`
```
---
name: verify-before-claiming
description: Use whenever you are about to say a check passed, tests pass, or something is clean or fixed. Never make that claim without pasting the real command output that backs it, in the same response.
---

Before you write "checkov passes," "tests pass," "it's clean," or any similar completion claim,
run the real command and include its real output. A claim with no evidence attached is a guess.
```

A skill is words the agent reads. Words get skipped under time pressure. The next step is what
actually stops it.

### Step 4: Write the hook that enforces it

`file: hooks/verify_claim.sh`
```
CLAIM_RE='(checkov (passes|is clean|clean)|tests? pass(es)?|it works|this works|is clean now|no (more )?findings)'
EVIDENCE_RE='(Passed checks: [0-9]+, Failed checks: [0-9]+|Check: CKV|exit code:? *0|\$ checkov)'

if ! grep -Eiq "$CLAIM_RE" "$FILE"; then
  echo "PASS: no completion claim found, nothing to verify"
  exit 0
fi

if grep -Eiq "$EVIDENCE_RE" "$FILE"; then
  echo "PASS: completion claim found, and real command evidence backs it up"
  exit 0
fi

echo "BLOCK: completion claim found with no real command evidence in the transcript" >&2
exit 1
```

This is the whole mechanism: scan the response for a completion phrase, require real evidence
sitting next to it, block if it's missing. `[...]` see `hooks/verify_claim.sh` in this repo for the
full script.

### Step 5: Run the hook twice, for real

**Run 1**, the unbacked claim from earlier, saved as a plain-text transcript:

```
./hooks/verify_claim.sh evidence/unbacked-claim.txt
```

`[ Expected output ]`
```
BLOCK: completion claim found with no real command evidence in the transcript
```

`Exit code 1`. **Run 2**, the same kind of claim, this time with the real checkov output from the
fixed module sitting right beside it:

```
./hooks/verify_claim.sh evidence/backed-claim.txt
```

`[ Expected output ]`
```
PASS: completion claim found, and real command evidence backs it up
```

`Exit code 0`. Same words, same kind of claim. The only thing that changed between a block and a
pass is whether the evidence was actually there.

### Step 6: Fix the bucket, apply, and destroy

`edit file: starter/main.tf`, add versioning and a public access block (or copy
`solution/main.tf`), then confirm the two targeted findings are gone:

```
checkov -d starter --compact --quiet
```

`[ Expected output ]`
```
Passed checks: 11, Failed checks: 5, Skipped checks: 0
```

Notice what's still there: 5 real findings (event notifications, lifecycle, access logging, KMS
encryption, cross-region replication), left honestly unfixed. This project's harness checks for
versioning and a public access block, not everything checkov knows about. A harness enforces what
it was told to enforce, same lesson as M07's spec-scope.

**Apply** and **destroy** against Floci, the real thing, not a claim about it:

```
terraform -chdir=starter apply -auto-approve
terraform -chdir=starter destroy -auto-approve
```

## Stage 2: Prove test-first, RED before GREEN

The second superpowers discipline. The iron law: no fix without a failing test first, watched
failing for the right reason, before you write a single line of the fix.

```
cd tdd
```

`file: tdd/main.tf` is the same bucket, no encryption yet. `file: tdd/test_encryption.sh` is the
test, written **before** the fix exists, checking one real thing: `CKV_AWS_145`, the S3
default-encryption check.

### Step 1: Run RED against the unfixed bucket

```
./test_encryption.sh
```

`[ Expected output ]`
```
RED: aws_s3_bucket.artifacts is not encrypted yet
Check: CKV_AWS_145: "Ensure that S3 buckets are encrypted with KMS by default"
	FAILED for resource: aws_s3_bucket.artifacts
	File: /main.tf:32-38
```

`Exit code 1`. Read that output before you touch anything. That's a real failure: the check
caught a real gap, not a typo or a missing file. That's what "verify RED" means, confirm the test
fails for the reason you expect, not any reason.

### Step 2: Write the fix and run GREEN

Write the minimal fix, an `aws_s3_bucket_server_side_encryption_configuration` resource:

```
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}
```

Add that block to `tdd/main.tf` (or copy `tdd/solution/main.tf`), then rerun the exact same test:

```
./test_encryption.sh
```

`[ Expected output ]`
```
GREEN: aws_s3_bucket.artifacts is encrypted with a default KMS key
```

`Exit code 0`. Same script, same check, only the module changed. **Refactor** is the third step of
the cycle and it's honest to skip it here, five lines of HCL have nothing worth cleaning up. Don't
add a refactor step just to look complete. A refactor step exists to remove duplication or improve
names.

## Stage 3: Find a real root cause, the 3-Fix Rule

The third discipline. `lab/debug/main.tf` has a real bug, not staged: it uses `endpoint_url`, the
argument name Floci's own README shows. `CLAUDE.md`'s own retired-tools table already flags this,
you're about to see why it's flagged.

### Step 1: Reproduce the real bug

```
cd ../debug
terraform init -backend=false -input=false >/dev/null
terraform validate
```

`[ Expected output ]`
```
Error: Unsupported argument

  on main.tf line 21, in provider "aws":
  21:   endpoint_url = "http://localhost:4566"

An argument named "endpoint_url" is not expected here.
```

That's the symptom. Now three real, plausible, wrong fixes, the ones an engineer under pressure
actually reaches for.

### Step 2: Try three wrong fixes

**Attempt 1, assume it's a provider-version mismatch.** Pin an exact version, reinit:

```
sed -i.bak 's/version = "~> 6.0"/version = "6.15.0"/' main.tf
rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false >/dev/null
terraform validate
```

`[ Expected output ]`
```
Error: Unsupported argument
  on main.tf line 21, in provider "aws":
  21:   endpoint_url = "http://localhost:4566"
An argument named "endpoint_url" is not expected here.
```

Same error. Wrong hypothesis. `mv main.tf.bak main.tf` to undo it.

**Attempt 2, assume it's a stale cache.** Wipe `.terraform` and the lock file, reinit clean:

```
rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false >/dev/null
terraform validate
```

`[ Expected output ]`
```
Error: Unsupported argument
  on main.tf line 21, in provider "aws":
  21:   endpoint_url = "http://localhost:4566"
An argument named "endpoint_url" is not expected here.
```

Same error again. Wrong hypothesis.

**Attempt 3, guess the argument is just misnamed.** Try `endpoints_url`:

```
sed -i.bak2 's/endpoint_url = /endpoints_url = /' main.tf
rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false >/dev/null
terraform validate
```

`[ Expected output ]`
```
Error: Unsupported argument
  on main.tf line 21, in provider "aws":
  21:   endpoints_url = "http://localhost:4566"
An argument named "endpoints_url" is not expected here.
```

Still an unsupported argument, different name, same kind of failure. **This is the 3-Fix Rule.**
Three attempts, three failures, each one a different guess at the same wrong layer. Debugging's own
rule says stop here and question the architecture, not attempt a fourth guess.

### Step 3: Find the real root cause and apply it

**Stop and compare against a known-working example**, the actual root-cause move: `undo` both
sed edits, then diff this file's provider block against
`labs/shared/floci-spike/provider.tf`, the stub every Tier-1 lab in this course already uses. The
real difference is structural: AWS's provider does not take a flat `endpoint_url` string, it
takes a structured `endpoints {}` block, one key per service.

```
mv main.tf.bak main.tf
```

`edit file: debug/main.tf`, replace the broken line with the correct structure (or copy
`lab/debug/solution/main.tf`):

```
  endpoints {
    s3 = "http://localhost:4566"
  }
```

```
rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false >/dev/null
terraform validate
```

`[ Expected output ]`
```
Success! The configuration is valid.
```

**Apply and destroy against real Floci**, proof the root-cause fix actually works, not just that
`validate` stopped complaining:

```
terraform apply -auto-approve
terraform destroy -auto-approve
```

Three wrong guesses are the evidence that rules out the wrong layer, before you question the
architecture. A fourth guess without that evidence is what debugging's iron law exists to stop.

#### Exercise

Write a hook, or extend this one, for a discipline your own team skips under deadline pressure.
Test it two ways: make it block a real bad case, make it pass a real good one. Prove it blocks
something real, or it is not a hook yet.

## Validation

Run the full harness check yourself, all three disciplines, start to finish, against real Floci
and real checkov:

```
cd modules/module-08-harness-engineering/lab
./run.sh
```

`run.sh` checks:

- The starter bucket fails checkov for real (`CKV_AWS_21`, `CKV2_AWS_6`), the solution bucket
  passes both
- The hook blocks the unbacked claim and passes the backed one
- The test-first cycle fails RED for the right reason (`CKV_AWS_145`) and passes GREEN after the
  minimal fix
- The debug module fails `validate` with the real seeded bug, then applies and destroys cleanly
  against Floci once the root cause is fixed

## Summary

What you built:

- A verification harness for the S3 bucket module: a skill that states the rule, a hook that
  enforces it
- A real unbacked claim, blocked by your own hook, the same kind of claim passed once real
  evidence sat next to it
- A real test-first cycle: a check that failed for the right reason before the fix existed, and
  passed for the right reason after
- A real root-cause debug: three wrong fixes, each ruling out a layer, then the real root cause
  found by comparing against a known-working example
- A real `terraform apply` and `destroy` at every stage, against Floci

This is what M12 needs to be true before it's safe to let an agent loop unattended: a broken
harness looped just repeats its mistakes faster.
