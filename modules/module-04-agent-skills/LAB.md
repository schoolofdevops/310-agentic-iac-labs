# Lab 4: Write a Skill, Generate a Module, Verify Against Floci

**Tier 1** · ~20 min · Docker socket mounted, `floci/floci:1.7.0` pinned, real `terraform apply`
and `destroy` against it.

M03 gave the agent standing context, information that's true every run. This lab gives it
standing capability instead: a skill it reaches for on its own when a task matches, not
something you have to re-explain every time. You'll write one, use it, and prove the
difference against a real Tier 1 provider.

## Pre Requisites

- Completed M01 and M03, or at least read both modules' `reading/concepts.md`
- Docker reachable at `/var/run/docker.sock`, same check as every Tier 1 lab in this course:

```
docker info
```

## Read the worked example first

Before writing your own skill, **read** the one already in this repo:

`file: demos/m1-agent-preview/.claude/skills/container-conventions/SKILL.md`

Notice the shape: a YAML frontmatter with `name` and `description`, then plain instructions
in the body. The `description` field is the whole game. It's what an agent matches against
when deciding whether this skill applies to the task in front of it. A vague description
means the skill sits there, written, correct, and never triggered.

## Run 1: no skill available

Copy the starter into a scratch directory, with no `.claude/skills/` anywhere in it:

```
cp -r modules/module-04-agent-skills/lab/starter ~/m04-run1
cd ~/m04-run1
```

The intent handed to the agent, no skill loaded:

> Give me a small S3 bucket for build artifacts, with a credential for the uploader sidecar
> that ships them there.

`file: ~/m04-run1/main.tf`
```
variable "artifact_uploader_key" {
  description = "AWS key for the sidecar that uploads build artifacts to S3"
  type        = string
  default     = "AKIAQRSTUVWXYZ012345"
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "m04-lab-build-artifacts"
}
```

No `tags` block. No provider version pin in `provider.tf`. And the same mistake M01's lab
caught by hand: a credential sitting in a `default`. **Scan** it:

```
terraform fmt -check
terraform init -backend=false && terraform validate
checkov -d . --framework secrets
```

`[ Expected output ]`
```
Success! The configuration is valid.

secrets scan results:

Passed checks: 0, Failed checks: 1, Skipped checks: 0

Check: CKV_SECRET_2: "AWS Access Key"
	FAILED for resource: 7cfe6c0f3efbed208df755d8278ea68915b97450
	File: /main.tf:9-10
```

`Exit code 1`. Unlike M01's `docker_container` and `local_file` resources, a real
`aws_s3_bucket` also picks up several S3-hardening findings from checkov's terraform
framework, missing encryption, missing versioning, and so on. Leave those for now. This
module's skill isn't scoped to fix general S3 posture, that's a systematic job for M09's
scanners. This skill is scoped to three things: provider pins, required tags, and secrets.

## Write the skill

**Write** the skill that was missing. This is the deliverable of this lab, not a formality:

`file: .claude/skills/terraform-module-conventions/SKILL.md`
```
---
name: terraform-module-conventions
description: House rules for any Terraform module written against this repo's AWS-shaped provider (Floci or real AWS). Use whenever asked to write, generate, or extend a Terraform module for an AWS resource.
---

# Terraform module conventions

Apply these rules to every Terraform module in this repo, whether or not the request
mentions them by name.

## Provider pins

- Pin the `aws` provider to `~> 6.0`, exactly as declared in
  `labs/shared/floci-spike/provider.tf`.

## Required tags

- Every taggable resource gets a `tags` block with at least `Environment`, `Owner`, and
  `ManagedBy`.

## Secrets

- Never a secret in a `default`. Every credential-shaped variable is `sensitive = true`,
  with no default, set via `TF_VAR_<name>` at runtime.
```

Keep the `description` specific. "Use whenever asked to write, generate, or extend a
Terraform module for an AWS resource" names the exact trigger. A description like "Terraform
best practices" is vague enough that an agent has nothing solid to match against, and the
skill goes unused.

## Run 2: skill available

Copy a fresh starter, put the skill next to it, and hand the agent the exact same intent:

```
cp -r modules/module-04-agent-skills/lab/starter ~/m04-run2
mkdir -p ~/m04-run2/.claude/skills
cp -r .claude/skills/terraform-module-conventions ~/m04-run2/.claude/skills/
cd ~/m04-run2
```

This module's captured, real run 2 is `lab/solution/main.tf`, produced with the skill in
place:

`file: lab/solution/main.tf`
```
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
```

Provider pin, required tags, no hardcoded secret, all three rules applied without you typing
any of them into the prompt. **Re-run** the same scan:

```
terraform fmt -check
terraform init -backend=false && terraform validate
checkov -d . --framework secrets
```

`[ Expected output ]`
```
Success! The configuration is valid.
```

`Exit code 0`. No secrets finding at all, not "0 failed", nothing to report. The S3-hardening
findings from the terraform framework are still there, same count as run 1, because the
skill was never scoped to fix those. That's the point: a skill fixes what it says it fixes,
nothing more.

## Apply and destroy against Floci

**Start** Floci per the Tier 1 rules used across this course:

```
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0
```

**Apply** the module with the skill's fixes in place:

```
export TF_VAR_artifact_uploader_key="AKIAFAKELABKEY000111"
terraform apply -auto-approve
```

`[ Expected output ]`
```
aws_s3_bucket.artifacts: Creating...
aws_s3_bucket.artifacts: Creation complete after 0s [id=m04-lab-build-artifacts]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

A real bucket, in a real backend container, not a plan file. **Destroy** it, the same
numbered step every Tier 1 lab in this course ends with:

```
terraform destroy -auto-approve
docker rm -f floci
```

`[ Expected output ]`
```
aws_s3_bucket.artifacts: Destroying... [id=m04-lab-build-artifacts]
aws_s3_bucket.artifacts: Destruction complete after 0s

Destroy complete! Resources: 1 destroyed.
```

## Which failure was which

Same seam M03 opened, one module later: not every fix in this lab came from the same layer.

- The missing tags, the missing pin, and the hardcoded secret were all context-shaped
  problems the skill fixed on the first try, because the rule was written where the agent
  could read it and matched by a specific `description`
- The S3-hardening gaps, missing encryption, missing versioning, are not something a skill
  fixes by being invoked once. They need a gate that runs on every module, whether or not an
  agent decides to reach for a skill. That's the harness, coming in M06 and M08

#### Exercise

Take the `description` field in your skill and make it vague on purpose, something like
"Terraform best practices." Ask the same agent the same intent a third time. Does the skill
still get used? Write two lines in `notes.md`: what changed, and why a specific trigger
phrase matters more than a complete rule set nobody ever reaches.

#### Summary

You wrote a skill, watched an agent apply it without being told to on the second run, and
applied and destroyed a real module against Floci. The skill fixed exactly three things:
provider pin, required tags, secrets. It didn't fix S3 hardening, and it isn't supposed to.
M06 picks up the next layer: a gate that runs whether or not an agent chooses to use
anything.

##### Reading List

- `demos/m1-agent-preview/.claude/skills/container-conventions/SKILL.md`, the worked example
  this lab's skill is modeled on
- `reading/concepts.md` in this module: the context vs skill vs prompt distinction
- `labs/shared/floci-spike/provider.tf`: the canonical Tier 1 provider stub this lab reuses

##### Search Keywords

- Agent Skill, SKILL.md, frontmatter, description field, discoverability
- terraform-module-conventions
- CKV_SECRET_2, checkov secrets framework, checkov terraform framework
- floci, Tier 1 lab, apply, destroy

##### Re-verify

`lab/run.sh` checks both runs for real: run 1 must fail the secrets scan, run 2 must be
clean and carry the required tags and provider pin, then it applies and destroys the
solution module against a real Floci container. Run it whenever the pinned provider,
checkov, or Floci versions in this lab get bumped:

```
cd modules/module-04-agent-skills/lab
./run.sh
```
