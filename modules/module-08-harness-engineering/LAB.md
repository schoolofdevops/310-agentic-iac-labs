# Lab 8: Build a Verification-Before-Claiming Harness

**Tier 1** · ~20 min · Docker socket mounted, `floci/floci:1.7.0` pinned, provider stub copied from
`labs/shared/floci-spike/provider.tf`, same rules as every Tier 1 lab in this course.

M04 gave you a skill. M05 gave you a live MCP connection. M06 gave you a hook. Today you **assemble**
them into one thing: a harness that will not let an agent claim a check passed unless the real
output backing that claim is actually there.

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

#### Exercise

Write a hook, or extend this one, for a discipline your own team skips under deadline pressure.
Test it two ways: make it block a real bad case, make it pass a real good one. If you can't make it
block anything, it isn't a hook yet, it's a comment.

#### Summary

You assembled a harness out of pieces you already had: a skill that states the rule, a hook that
enforces it whether or not the rule gets read carefully. You watched an unbacked claim slip through
with no harness, then watched the same shape of claim get blocked and passed depending on nothing
but the evidence attached to it. This is what M12 needs to be true before it's safe to let an agent
loop unattended: a broken harness looped just repeats its mistakes faster.

##### Reading List

- [Checkov docs: S3 bucket checks](https://www.checkov.io/5.Policy%20Index/terraform.html)
- `reading/concepts.md` in this module: the superpowers pattern in full, and why harness and
  context are different diagnoses for different symptoms

##### Search Keywords

- harness engineering, assembled harness
- verification-before-claiming, test-first, root-cause debugging
- Claude Code hooks, Stop hook, PreToolUse hook
- checkov, CKV_AWS_21, CKV2_AWS_6
