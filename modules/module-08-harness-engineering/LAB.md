# Lab 8: Build a Verification-Before-Claiming Harness

**Tier 1** · ~20 min · Docker socket mounted, `floci/floci:1.7.0` pinned, provider stub copied from
`labs/shared/floci-spike/provider.tf`, same rules as every Tier 1 lab in this course.

M04 gave you a skill. M05 gave you a live MCP connection. M06 gave you a hook. Today you **assemble**
them into one thing: a harness built on the superpowers pattern, three real disciplines, not one.
You'll run all three for real: verification-before-claiming (a hook that blocks an unbacked
claim), test-first (a real RED-GREEN cycle against a Terraform module), and root-cause debugging
(a real bug, three real wrong fixes, then the real root cause).

## Pre Requisites

- Docker reachable at `/var/run/docker.sock`. Check with `docker info`
- `terraform` and `checkov` available (base devcontainer image)

## Get the starter module

```
cp -r modules/module-08-harness-engineering/lab/starter ~/m08-lab
cp -r modules/module-08-harness-engineering/lab/hooks ~/m08-lab/hooks
cd ~/m08-lab
```

`file: ~/m08-lab/starter/main.tf`
```
resource "aws_s3_bucket" "artifacts" {
  bucket = "m08-lab-artifacts"

  tags = {
    owner = "platform-team"
  }
}
```

## No harness: watch a claim slip through

Ask an agent (or narrate it yourself, the point survives either way) to review this bucket and
confirm it's clean. Nothing stops it from answering:

> "Looks good, checkov passes, the module is clean."

**Run** the real scan and check whether that claim was true:

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

Seven real failures, and the claim said "clean." Nothing mechanical stopped that gap from reaching
you. That's the failure this lab fixes.

## Write the skill: state the rule

`file: ~/m08-lab/.claude/skills/verify-before-claiming/SKILL.md`
```
---
name: verify-before-claiming
description: Use whenever you are about to say a check passed, tests pass, or something is clean or fixed. Never make that claim without pasting the real command output that backs it, in the same response.
---

Before you write "checkov passes," "tests pass," "it's clean," or any similar completion claim,
run the real command and include its real output. A claim with no evidence attached is not done,
it's a guess.
```

A skill is words the agent reads. Words get skipped under time pressure. The next step is what
actually stops it.

## Write the hook: enforce it mechanically

`file: ~/m08-lab/hooks/verify_claim.sh`
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

## Run it, twice, for real

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

`Exit code 0`. Same words, same shape of claim. The only thing that changed between a block and a
pass is whether the evidence was actually there.

## Fix it for real, apply, destroy

`edit file: ~/m08-lab/starter/main.tf`, add versioning and a public access block (or copy
`lab/solution/main.tf`), then confirm the two targeted findings are gone:

```
checkov -d . --compact --quiet
```

`[ Expected output ]`
```
Passed checks: 11, Failed checks: 5, Skipped checks: 0
```

Notice what's still there: 5 real findings (event notifications, lifecycle, access logging, KMS
encryption, cross-region replication), left honestly unfixed. This lab's harness checks for
versioning and a public access block, not everything checkov knows about. A harness enforces what
it was told to enforce, same lesson as M07's spec-scope.

**Apply** and **destroy** against Floci, the real thing, not a claim about it:

```
terraform apply -auto-approve
terraform destroy -auto-approve
```

## Test-first: RED before GREEN, for real

The second superpowers discipline. Not "write a test at some point," the iron law: no fix without
a failing test first, and you have to watch it fail for the right reason before you write a single
line of the fix.

```
cd ~/m08-lab
cp -r modules/module-08-harness-engineering/lab/tdd .
cd tdd
```

`file: tdd/main.tf` is the same bucket, no encryption yet. `file: tdd/test_encryption.sh` is the
test, written **before** the fix exists, checking one real thing: `CKV_AWS_145`, the S3
default-encryption check.

**RED.** Run it against the unfixed bucket:

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

`Exit code 1`. Read that output before you touch anything. It didn't fail because of a typo or a
missing file, it failed because the real check is real. That's what "verify RED" means, confirm the
test fails for the reason you expect, not any reason.

**GREEN.** Now write the minimal fix, an `aws_s3_bucket_server_side_encryption_configuration`
resource:

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
add a refactor step just to look complete, a real refactor step exists to remove duplication or
improve names, not to pad a lab.

## Root-cause debugging: the 3-Fix Rule, for real

The third discipline. `lab/debug/main.tf` has a real bug, not staged: it uses `endpoint_url`, the
argument name Floci's own README shows. `CLAUDE.md`'s own retired-tools table already flags this,
you're about to see why it's flagged.

```
cd ~/m08-lab
cp -r modules/module-08-harness-engineering/lab/debug .
cd debug
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

Still an unsupported argument, different name, same shape of failure. **This is the 3-Fix Rule.**
Three attempts, three failures, each one a different guess at the same wrong layer. Debugging's own
rule says stop here and question the architecture, not attempt a fourth guess.

**Stop and compare against a known-working example**, the actual root-cause move: `undo` both
sed edits, then diff this file's provider block against
`labs/shared/floci-spike/provider.tf`, the stub every Tier-1 lab in this course already uses. The
real difference isn't a version or a typo, it's the shape: AWS's provider doesn't take a flat
`endpoint_url` string at all, it takes a structured `endpoints {}` block, one key per service.

```
mv main.tf.bak main.tf
```

`edit file: debug/main.tf`, replace the broken line with the real shape (or copy
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

Three wrong guesses is not wasted time, it's the evidence that rules out the wrong layer before you
question the architecture. A fourth guess without that evidence is what debugging's iron law
exists to stop.

#### Exercise

Write a hook, or extend this one, for a discipline your own team skips under deadline pressure.
Test it two ways: make it block a real bad case, make it pass a real good one. If you can't make it
block anything, it isn't a hook yet, it's a comment.

#### Summary

You ran all three superpowers disciplines for real, not as prose. Verification-before-claiming: an
unbacked claim blocked, the same shape of claim passed once real evidence sat next to it.
Test-first: a real check that failed for the right reason before the fix existed, and passed for
the right reason after. Root-cause debugging: three real wrong fixes, each ruling out a layer, then
a real root cause found by comparing against a known-working example, applied and destroyed against
real Floci. This is what M12 needs to be true before it's safe to let an agent loop unattended: a
broken harness looped just repeats its mistakes faster.

##### Reading List

- [Checkov docs: S3 bucket checks](https://www.checkov.io/5.Policy%20Index/terraform.html)
- `reading/concepts.md` in this module: the superpowers pattern in full, and why harness and
  context are different diagnoses for different symptoms
- `~/.claude/superpowers/tdd.md`, `verification.md`, `debugging.md`: the source discipline this
  lab's three exercises are built from

##### Search Keywords

- harness engineering, assembled harness
- verification-before-claiming, test-first, root-cause debugging
- red-green-refactor, the 3-Fix Rule
- Claude Code hooks, Stop hook, PreToolUse hook
- checkov, CKV_AWS_21, CKV2_AWS_6, CKV_AWS_145
