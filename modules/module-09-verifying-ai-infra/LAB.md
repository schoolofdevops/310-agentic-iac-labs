# Project 09: Build a Scan-and-Policy Pipeline for a Real S3 Module

**Tier 1** · ~20 min · Docker socket mounted, `floci/floci:1.7.0` pinned, provider stub from
`labs/shared/floci-spike/provider.tf`, same Tier 1 rules as every hands-on project since M04.

In this project, you will build the pipeline that decides whether a real Terraform module is
safe to apply, the same sentence you have carried since module one: the agent proposes, the
pipeline decides. The module itself is already written: a reports-and-backups S3 service, two
buckets, one deliberately left unhardened.

**What you're building, at a glance:**

- Both scanners run yourself, against a real 21-resource module and against this project's own
  module, reproducing the exact numbers from the reading
- **A real Checkov finding Trivy never reports**, proof the two tools don't cover the same
  ground
- **A real OPA policy**, written from scratch, for a rule neither scanner can ever know
- **A real cost gate**, wired honestly: it runs for real if you have an Infracost key, and
  skips with a clear message if you don't, never a guessed number
- **A five-stage pipeline script** that blocks on the first real failure, cheap checks first
- **A deterministic eval rubric**, run against a real agent's own Terraform output, checking
  the agent's claim rather than the infrastructure

## Pre Requisites

- Docker reachable, same check as every Tier 1 lab:

```
docker info
```

- `trivy`, `checkov`, and `conftest` on your `PATH`. If you're in the devcontainer they're
  already there. Check with:

```
trivy --version
checkov --version
conftest --version
```

## Step 1: Reproduce the opening demo, live

Before touching this lab's own module, reproduce the number from the reading, on the real
21-resource module already in this repo:

```
cd labs/shared/floci-spike
trivy config --quiet --severity HIGH,CRITICAL .
checkov -d . --compact --quiet --framework terraform --skip-download
```

`[ Expected output ]`
```
Tests: 4 (SUCCESSES: 0, FAILURES: 4)
...
Tests: 1 (SUCCESSES: 0, FAILURES: 1)
...
Tests: 2 (SUCCESSES: 0, FAILURES: 2)
...
terraform scan results:

Passed checks: 60, Failed checks: 25, Skipped checks: 0
```

Add up Trivy's HIGH and CRITICAL failures across its three grouped reports: 4 + 1 + 2 = **7**.
Checkov's own summary line says **25** directly. Same numbers as the reading, reproduced on
your own machine.

## Step 2: Run Trivy and Checkov

**Copy** the lab module into your own working directory, same pattern as every lab since M01:

```
cp -r modules/module-09-verifying-ai-infra/lab ~/m09-lab
cd ~/m09-lab
```

`file: ~/m09-lab/module/main.tf` is a small, two-bucket module, deliberately unhardened.
**Scan** it with both tools:

```
trivy config --quiet --severity HIGH,CRITICAL module
checkov -d module --compact --quiet --framework terraform --skip-download
```

`[ Expected output ]`
```
Tests: 16 (SUCCESSES: 0, FAILURES: 16)
Failures: 16 (LOW: 4, MEDIUM: 2, HIGH: 10, CRITICAL: 0)
...
terraform scan results:

Passed checks: 9, Failed checks: 14, Skipped checks: 0
```

**Read** one Checkov finding Trivy never reported at all:

```
Check: CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled"
	FAILED for resource: aws_s3_bucket.reports
```

Search Trivy's 16 findings for anything about replication. There isn't one. Trivy's rule set
for this resource type doesn't encode it. That's the coverage gap from the reading, made
concrete: Checkov's own rule set is the strictly larger one here, and only running Trivy
would have missed this finding entirely.

## Step 3: Write an OPA Policy

Your org has one rule neither Trivy nor Checkov can ever check: every `aws_s3_bucket` must
carry an `Owner` tag. **Write** it as a real OPA policy:

`file: ~/m09-lab/policy/required_tags.rego`
```
package main

import rego.v1

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_s3_bucket"
	tags := object.get(rc.change.after, "tags", {})
	not tags.Owner
	msg := sprintf("%s has no Owner tag: every aws_s3_bucket must carry tags.Owner", [rc.address])
}
```

**Plan** the unhardened module and check it against the policy:

```
terraform -chdir=module init -backend=false -input=false
terraform -chdir=module plan -out=/tmp/plan.bin -var="endpoint=http://localhost:4566"
terraform -chdir=module show -json /tmp/plan.bin > /tmp/plan.json
conftest test --policy policy /tmp/plan.json
```

`[ Expected output ]`
```
FAIL - /tmp/plan.json - main - aws_s3_bucket.reports has no Owner tag: every aws_s3_bucket must carry tags.Owner

1 test, 0 passed, 0 warnings, 1 failure, 0 exceptions
```

`Exit code 1`. `aws_s3_bucket.reports` has no tags at all in the starter module; `backups`
already does. **Fix**, re-plan, re-check:

`file: ~/m09-lab/solution/main.tf` already has this fixed, both buckets carry
`Owner = "m09-lab"`. Point `conftest` at the solution's plan instead and it passes clean,
`1 test, 1 passed, 0 warnings, 0 failures, 0 exceptions`.

## Step 4: Wire Infracost

Infracost's own CLI needs a one time, free device login the first time you use it, no card:

```
infracost auth login
```

Once you've done that once, `INFRACOST_API_KEY` (or a saved session) is what turns this
stage on. This lab's own `pipeline.sh` checks for it and does the honest thing either way:
runs the real estimate if you have a key, or skips the stage with a clear message if you
don't, never a guessed number.

## Step 5: Assemble the pipeline

`file: lab/pipeline.sh` in this repo is the reference version, five stages, in the order
the reading argued for: fmt/validate, trivy, checkov, conftest, infracost, each one able to
stop everything after it. **Run** it against the starter module first:

```
./pipeline.sh module
```

`[ Expected output ]`
```
==> stage 1/5: fmt + validate
Success! The configuration is valid.

==> stage 2/5: trivy
...
BLOCKED at trivy
```

`Exit code 1`, stopped at stage 2. Now the solution:

```
./pipeline.sh solution
```

`[ Expected output ]`
```
==> stage 1/5: fmt + validate
Success! The configuration is valid.

==> stage 2/5: trivy
    trivy: no HIGH/CRITICAL findings
==> stage 3/5: checkov
    checkov: no unreviewed findings
==> stage 4/5: conftest (org policy: every aws_s3_bucket needs tags.Owner)

1 test, 1 passed, 0 warnings, 0 failures, 0 exceptions
==> stage 5/5: cost gate (infracost)
    SKIPPED: no INFRACOST_API_KEY set. Run 'infracost auth login' once (free, no card)
    to enable this stage for real. See reading/reference.md.

PIPELINE PASSED for solution: every stage that could run, ran for real and passed
```

`Exit code 0`. Notice `solution/main.tf` still carries a few checkov findings by design,
event notifications, lifecycle, and cross-region replication, all deferred with a written
reason right in the file, and passed to `checkov` on the CLI with `--skip-check` rather
than an inline comment. Inline `#checkov:skip` comments were tested against this exact
checkov version and did not actually suppress those findings, the CLI flag did. That's
worth remembering the next time a suppression silently doesn't work: verify it did.

## Step 6: Evaluate the Agent's Output

Everything so far in this project checks the *infrastructure*. This step checks the
*agent's output* against a rubric, a different question: whether the agent did what it was
actually asked, regardless of whether the bucket it produced happens to be safe.

**Write** a deterministic rubric, plain Python, no model involved, that checks an agent's
Terraform output against M04's own required-tags convention (`Environment`, `Owner`,
`ManagedBy`):

`file: eval/rubric.py`
```python
#!/usr/bin/env python3
"""Deterministic rubric: does this Terraform output tag every S3 bucket the way
M04's convention requires? No model involved, plain text parsing, exit 0 or 1."""
import re
import sys

REQUIRED_TAGS = ["Environment", "Owner", "ManagedBy"]


def find_bucket_blocks(text):
    blocks = []
    for match in re.finditer(r'resource\s+"aws_s3_bucket"\s+"([^"]+)"\s*\{', text):
        name = match.group(1)
        start = match.end()
        depth = 1
        i = start
        while depth > 0 and i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        blocks.append((name, text[start:i]))
    return blocks


def check(path):
    text = open(path, encoding="utf-8").read()
    blocks = find_bucket_blocks(text)
    if not blocks:
        return False, ["no aws_s3_bucket resource found"]
    violations = []
    for name, body in blocks:
        missing = [t for t in REQUIRED_TAGS if t not in body]
        if missing:
            violations.append(f"aws_s3_bucket.{name}: missing tags {missing}")
    return (not violations), violations


if __name__ == "__main__":
    ok, violations = check(sys.argv[1])
    if ok:
        print(f"PASS: every bucket in {sys.argv[1]} carries {REQUIRED_TAGS}")
        sys.exit(0)
    print(f"FAIL: {sys.argv[1]} does not meet the tagging rubric")
    for v in violations:
        print(" -", v)
    sys.exit(1)
```

**Run** it against a seeded failure first:

```
python3 eval/rubric.py eval/fixture-bad.tf
```

`[ Expected output ]`
```
FAIL: eval/fixture-bad.tf does not meet the tagging rubric
 - aws_s3_bucket.reports: missing tags ['Owner', 'ManagedBy']
 - aws_s3_bucket.backups: missing tags ['Environment', 'Owner', 'ManagedBy']
```

`Exit code 1`. `reports` is missing `Owner` and `ManagedBy`, `backups` has no `tags` block
at all.

**Run** it against a fixed fixture:

```
python3 eval/rubric.py eval/fixture-good.tf
```

`[ Expected output ]`
```
PASS: every bucket in eval/fixture-good.tf carries ['Environment', 'Owner', 'ManagedBy']
```

`Exit code 0`.

**Ask** a real agent to produce a third fixture, then grade it with the same rubric:

```
claude -p "Write a Terraform aws_s3_bucket resource named 'reports', bucket name m09-eval-reports-live. Tag it Environment=lab, Owner=m09-lab, ManagedBy=terraform-module-conventions-skill. Write only the resource block to eval/fixture-live.tf, nothing else." \
  --permission-mode acceptEdits --allowedTools "Write"

python3 eval/rubric.py eval/fixture-live.tf
```

This is what came back, captured for real, with no skill in the folder:

`[ Expected output ]`
```
PASS: every bucket in eval/fixture-live.tf carries ['Environment', 'Owner', 'ManagedBy']
```

`Exit code 0`. The agent tagged the bucket correctly because the prompt stated the tags
explicitly. The rubric would have caught it either way.

The rubric does not care how convincingly the agent explained its reasoning. It checks the
output against a fixed rule, the same discipline M04's bundled script brought to CIDR
checking, applied here to the agent's own claim about what it built.

#### Exercise

Add a third bucket to `module/main.tf`, on purpose leave its `Owner` tag off, and run
`conftest` again. Confirm it fails on the new bucket by name. Then fix it and confirm a
clean pass.

## Validation

Run the full pipeline yourself, both the starter module and the solution, against a real
Floci container:

```
cd modules/module-09-verifying-ai-infra/lab
./run.sh
```

`run.sh` checks:

- The opening demo reproduces on the real `floci-spike` module: Trivy 7, Checkov 25
- Both scanners run against this project's own module and agree the starter is unhardened
- The OPA policy fails on the starter module and passes on the solution
- `pipeline.sh` blocks at stage 2 on the starter module and passes all five stages on the
  solution
- The eval rubric rejects `eval/fixture-bad.tf` and accepts `eval/fixture-good.tf`

## Summary

What you built:

- Both scanners reproduced against a real module, same numbers as the reading
- A real Checkov finding Trivy never reported, the coverage gap made concrete
- A real OPA policy for the one rule neither scanner can check
- A cost gate wired to skip honestly, never to guess
- A five-stage pipeline that blocks on the first real failure, cheap checks first
- A deterministic eval rubric, graded against a real agent's own Terraform output

Scan with two tools because one alone is a coverage gap. Write the policy check for the rule
only your team knows. Treat cost as a gate, not a report. Assemble all of it in
cheap-to-expensive order, the thesis this course opened with, now real. M10 and M11 put this
same pipeline in front of a real CI system. The capstone puts it in front of everything you
build there.
