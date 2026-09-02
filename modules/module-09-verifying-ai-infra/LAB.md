# Lab 9: Run the Real Pipeline

**Tier 1** · ~20 min · Docker socket mounted, `floci/floci:1.7.0` pinned, provider stub from
`labs/shared/floci-spike/provider.tf`, same Tier 1 rules as every hands-on lab since M04.

The project in this lab is a real S3 module for a reports-and-backups service, two
buckets, `reports` and `backups`, one of them deliberately left unhardened. You are not
writing new Terraform. You are building the pipeline that decides whether this project's
Terraform is safe to apply, the same one you have carried as a sentence since module one:
the agent proposes, the pipeline decides.

You've read the numbers: identical code, Trivy 7 findings, Checkov 25. Now you run both
scanners yourself against this module, write the one rule neither tool knows, wire a cost
gate honestly, and assemble all of it into a single pipeline script that blocks on the
first real failure, exactly the shape `pipeline.sh` in this lab folder already is.

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

## Reproduce the opening demo, live

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

## Run both scanners on this lab's own module

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

## Write the rule neither tool knows

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

## The cost gate, honestly

Infracost's own CLI needs a one time, free device login the first time you use it, no card:

```
infracost auth login
```

Once you've done that once, `INFRACOST_API_KEY` (or a saved session) is what turns this
stage on. This lab's own `pipeline.sh` checks for it and does the honest thing either way:
runs the real estimate if you have a key, or skips the stage with a clear message if you
don't, never a guessed number.

## Assemble the pipeline

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

#### Exercise

Add a third bucket to `module/main.tf`, on purpose leave its `Owner` tag off, and run
`conftest` again. Confirm it fails on the new bucket by name, not just "something failed."
Then fix it and confirm a clean pass.

#### Summary

You built one project in this lab: a five stage pipeline that decides whether the
reports-and-backups module is safe to apply, not just a module. Scan with two tools
because one alone is a coverage gap, write the policy check for the rule only your team
knows, treat cost as a gate instead of a report, and assemble all of it in
cheap-to-expensive order, exactly the thesis module one opened with, now real. M10 and M11
put this same pipeline in front of a real CI system. The capstone puts it in front of
everything you build there.

##### Reading List

- [Trivy: Terraform misconfiguration scanning](https://trivy.dev)
- [Checkov: policy index](https://www.checkov.io/5.Policy%20Index/terraform.html)
- [Open Policy Agent: policy language](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Conftest documentation](https://www.conftest.dev/)
- [Infracost: getting started](https://www.infracost.io/docs/)

##### Search Keywords

- trivy config, checkov, --skip-check, --skip-download
- conftest, opa, rego, resource_changes
- infracost breakdown, infracost auth login
- cost gate, policy as code, plan-diff review
