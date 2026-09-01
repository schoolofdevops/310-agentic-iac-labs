# Lab 4: Write a Skill, Then Make It Ship Code

**Tier 1** · ~40 min · Docker socket mounted, `floci/floci:1.7.0` pinned, real `terraform apply`
and `destroy` against it.

M03 gave the agent standing context, information that's true every run. This lab gives it
standing capability instead: a skill it reaches for on its own when a task matches, not
something you have to re-explain every time.

Two parts, same idea, different depth. Part I writes a skill that's pure prose, house rules
an agent applies to a single S3 bucket. Part II is the real point of this module: a skill
that **bundles a real, deterministic script**, not just instructions, and uses it to scaffold
and validate a genuinely multi-environment VPC. Prose-only skills tell an agent what to do.
A skill with a bundled script gives it something to run, with an exit code that doesn't care
how convincingly the agent reasoned.

## Pre Requisites

- Completed M01 and M03, or at least read both modules' `reading/concepts.md`
- Docker reachable at `/var/run/docker.sock`, same check as every Tier 1 lab in this course:

```
docker info
```

## Part I: A skill that writes house rules

### Read the worked example first

Before writing your own skill, **read** the one already in this repo:

`file: demos/m1-agent-preview/.claude/skills/container-conventions/SKILL.md`

Notice the shape: a YAML frontmatter with `name` and `description`, then plain instructions
in the body. The `description` field is the whole game. It's what an agent matches against
when deciding whether this skill applies to the task in front of it. A vague description
means the skill sits there, written, correct, and never triggered.

### Run 1: no skill available

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

### Write the skill

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

### Run 2: skill available

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

### Apply and destroy against Floci

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

### Which failure was which

Same seam M03 opened, one module later: not every fix in this lab came from the same layer.

- The missing tags, the missing pin, and the hardcoded secret were all context-shaped
  problems the skill fixed on the first try, because the rule was written where the agent
  could read it and matched by a specific `description`
- The S3-hardening gaps, missing encryption, missing versioning, are not something a skill
  fixes by being invoked once. They need a gate that runs on every module, whether or not an
  agent decides to reach for a skill. That's the harness, coming in M06 and M08

#### Exercise: Part I

Take the `description` field in your skill and make it vague on purpose, something like
"Terraform best practices." Ask the same agent the same intent a third time. Does the skill
still get used? Write two lines in `notes.md`: what changed, and why a specific trigger
phrase matters more than a complete rule set nobody ever reaches.

## Part II: A skill that ships code, multi-environment VPC

Part I's skill was three paragraphs of prose. It worked, an agent read it and applied every
rule, but nothing in it was mechanically checked. If the agent had misjudged one line, nothing
would have caught it, the skill can only ever suggest. This part builds a skill with real
teeth: a bundled, deterministic script the skill runs as part of its own job, not something the
agent reasons its way through freehand.

The system: a shared VPC module, and three environments, dev, staging, and prod, that are
**materially different from each other**, not a tfvars file with one number changed.

`file: vpc/modules/vpc/variables.tf`
```
variable "environment"          { type = string }
variable "vpc_cidr"              { type = string }
variable "az_count"              { type = number }
variable "public_subnet_cidrs"   { type = list(string) }
variable "private_subnet_cidrs"  { type = list(string) }

variable "nat_strategy" {
  type = string
  validation {
    condition     = contains(["single", "per_az"], var.nat_strategy)
    error_message = "nat_strategy must be \"single\" or \"per_az\"."
  }
}
```

`nat_strategy` is the interesting one. `"single"` shares one NAT gateway across every private
subnet, cheap, and a single point of failure. `"per_az"` gives every AZ its own NAT gateway, so
one NAT outage never takes another AZ down with it. **Read** the full module at
`vpc/modules/vpc/main.tf`, then the three real environments:

| Environment | AZs | `nat_strategy` | Why |
|---|---|---|---|
| `vpc/envs/dev` | 1 | `single` | Cheapest failure mode, nobody's on call for it |
| `vpc/envs/staging` | 2 | `single` | Enough spread to catch AZ bugs, NAT redundancy not worth it here |
| `vpc/envs/prod` | 3 | `per_az` | The one place a NAT gateway outage actually needs to stay contained to one AZ |

This is the shape an agent has to reason about, not substitute variables into. Two environments
share `nat_strategy = "single"` and still differ in AZ count. Only prod pays for `per_az`.

### The skill that bundles a real script

**Read** `.claude/skills/vpc-environment-scaffold/SKILL.md`. Same frontmatter shape as Part I's
skill, but its instructions point at a real file:

`file: .claude/skills/vpc-environment-scaffold/scripts/check_cidr_overlap.py`
```
def find_overlaps(cidrs):
    envs = list(cidrs.items())
    conflicts = []
    for i in range(len(envs)):
        for j in range(i + 1, len(envs)):
            name_a, net_a = envs[i]
            name_b, net_b = envs[j]
            if net_a.overlaps(net_b):
                conflicts.append((name_a, net_a, name_b, net_b))
    return conflicts
```

Plain `ipaddress` arithmetic, no model involved. The skill's instructions tell the agent to run
this **before** touching any environment's `vpc_cidr`, not to eyeball the numbers and decide
they look fine. That's the actual difference this part of the lab is teaching: Part I's skill
could only ever suggest a correct answer. This one hands the agent a program with an exit code.

**Run** it against the three real environments as they stand:

```
python3 .claude/skills/vpc-environment-scaffold/scripts/check_cidr_overlap.py vpc/envs
```

`[ Expected output ]`
```
OK: no CIDR overlap across dev, prod, staging
```

### Seed a real bug, watch the script catch it

Copy the three environments' `terraform.tfvars` to a scratch directory, then break one on
purpose, staging's CIDR shrunk to overlap dev's:

```
mkdir -p /tmp/m04-overlap-test/dev /tmp/m04-overlap-test/staging /tmp/m04-overlap-test/prod
cp vpc/envs/dev/terraform.tfvars /tmp/m04-overlap-test/dev/
cp vpc/envs/staging/terraform.tfvars /tmp/m04-overlap-test/staging/
cp vpc/envs/prod/terraform.tfvars /tmp/m04-overlap-test/prod/
python3 -c "
p = '/tmp/m04-overlap-test/staging/terraform.tfvars'
text = open(p).read().replace('10.11.0.0/16', '10.10.128.0/17')
open(p, 'w').write(text)
"
python3 .claude/skills/vpc-environment-scaffold/scripts/check_cidr_overlap.py /tmp/m04-overlap-test
```

`[ Expected output ]`
```
CIDR OVERLAP DETECTED:
  dev (10.10.0.0/16) overlaps staging (10.10.128.0/17)
```

`Exit code 1`. A real collision, caught by arithmetic, not by an agent's judgment call about
whether two `/16` and `/17` blocks happen to share addresses. **Clean up** the scratch copy:

```
rm -rf /tmp/m04-overlap-test
```

### Apply and destroy dev against Floci

**Start** Floci per the Tier 1 rules used across this course:

```
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0
```

**Apply** the dev environment, the fastest of the three to prove the module is real, not a
directory of unused HCL:

```
cd vpc/envs/dev
export TF_VAR_endpoint="http://localhost:4566"
terraform init -backend=false -input=false
terraform apply -auto-approve
```

`[ Expected output ]`
```
module.vpc.aws_vpc.this: Creation complete after 0s [id=vpc-f9c4f9fe]
module.vpc.aws_nat_gateway.this[0]: Creation complete after 0s [id=nat-26db0bc3210fc76d2]

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:

nat_gateway_ids = [
  "nat-26db0bc3210fc76d2",
]
vpc_id = "vpc-f9c4f9fe"
```

A real VPC, a real internet gateway, a real NAT gateway with a real Elastic IP, two subnets,
two route tables, all twelve resources genuinely applied against Floci, not a plan file.
**Destroy** it, the same numbered step every Tier 1 lab in this course ends with:

```
terraform destroy -auto-approve
cd ../../../
docker rm -f floci
```

`[ Expected output ]`
```
module.vpc.aws_nat_gateway.this[0]: Destruction complete after 20s
module.vpc.aws_vpc.this: Destruction complete after 0s

Destroy complete! Resources: 12 destroyed.
```

The NAT gateway is the slow one, real destroy-time behavior Floci models even though it's an
API-shaped emulation, not a real network path.

### What each layer actually caught

- The CIDR overlap is a **skill problem with a deterministic answer**. There's no judgment
  call, two ranges either overlap or they don't, so the skill doesn't just tell the agent to
  "check for overlaps", it hands it a script that decides.
- Whether prod should be `per_az` and staging shouldn't is **not** something the script checks.
  That's a design decision written into the skill's prose, the same kind of house rule Part I
  taught, sitting right next to a rule the skill can mechanically enforce. A skill can carry
  both at once. Confusing "the script verified this" with "the agent decided this and I should
  double check" is the mistake to watch for once a skill starts bundling real code.

#### Exercise: Part II

Add a fourth environment, `qa`, 2 AZs, `nat_strategy = "single"`, CIDR `10.13.0.0/16`. Before
running `terraform validate`, run the overlap checker against `vpc/envs` with your new
environment in place. Then deliberately pick a CIDR that collides with `staging`'s
`10.11.0.0/16` and confirm the script still catches it. Write two lines in `notes.md`: what the
script caught that `terraform validate` never would have, and why.

#### Summary

Part I: a skill written in prose, watched an agent apply it without being told to on the second
run, applied and destroyed a real module against Floci. Part II: a skill that bundles a real
deterministic script, catches a real CIDR collision across three genuinely different
environments, and applies and destroys a twelve-resource VPC against Floci. The through-line:
a skill's prose can only ever be followed or misjudged. A skill's bundled script either exits 0
or it doesn't. Neither replaces the harness, M06 and M08's gates run whether or not an agent
chooses to reach for a skill at all, but a skill that ships code closes more of the gap between
"the agent tried to follow the rule" and "the rule was actually checked."

##### Reading List

- `demos/m1-agent-preview/.claude/skills/container-conventions/SKILL.md`, the worked example
  Part I's skill is modeled on
- `reading/concepts.md` in this module: the context vs skill vs prompt distinction, and what a
  bundled script changes about that distinction
- `labs/shared/floci-spike/provider.tf`: the canonical Tier 1 provider stub both parts reuse
- `.claude/skills/vpc-environment-scaffold/scripts/check_cidr_overlap.py`: the full script,
  worth reading end to end, it's under 60 lines

##### Search Keywords

- Agent Skill, SKILL.md, frontmatter, description field, discoverability
- terraform-module-conventions, vpc-environment-scaffold
- CKV_SECRET_2, checkov secrets framework, checkov terraform framework
- CIDR overlap, `ipaddress` module, NAT gateway, `nat_strategy`, multi-environment module
- floci, Tier 1 lab, apply, destroy

##### Re-verify

`lab/run.sh` checks both parts for real. Part I: run 1 must fail the secrets scan, run 2 must
be clean and carry the required tags and provider pin, then it applies and destroys the
solution module against a real Floci container. Part II: all three VPC environments must
`validate` clean, the overlap checker must pass on the real environments and correctly catch a
seeded collision in a scratch copy, then it applies and destroys the dev environment's twelve
resources against a real Floci container. Run it whenever the pinned provider, checkov, or
Floci versions in this lab get bumped:

```
cd modules/module-04-agent-skills/lab
./run.sh
```
