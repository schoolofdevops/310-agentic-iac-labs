# Project 07: Build an Autoscaling Web Tier Using Spec-Driven Development

**Tier 1** · ~30 min · Terraform, Checkov, and Floci, same setup as the last few labs.

In this project, you will write a spec for a real autoscaling web tier, generate a module
against it, then answer the exact same one-line ticket a second time with no spec at all, and
compare the two against real applied infrastructure.

**What you're building, at a glance:**

- A real spec, requirements, constraints, and success criteria, for a checkout service's
  autoscaling tier
- A module generated from that spec, every line traced back to a requirement
- The same one-line ticket answered again, this time with no spec
- Five real judgment calls where the two versions genuinely diverge, checked against real
  `terraform plan` output
- A real `terraform apply` and `destroy` of the spec-driven version against Floci, checked
  against its own success criteria

## Pre Requisites

- The Docker socket reachable at `/var/run/docker.sock`, same as every Tier 1 lab so far.
- `terraform` and `checkov` on your `PATH`.

## The ticket

Here it is, verbatim, the way it would land in your queue:

> Give me an autoscaling web tier for our checkout service.

Read it again. It says nothing about how long a slow-starting instance gets before it's assumed
dead, which instance dies first when the tier scales in, how big "auto" is allowed to get, or how
fast it should react to a real spike. That silence is normal. Most tickets look exactly like this,
and an autoscaling group has more places for that silence to turn into a real decision than a
single S3 bucket ever did.

## Step 1: Write the spec

You could start typing Terraform right now. Don't. **Write** a spec first: what this tier must do,
what it must never do, and how you'll know it's right, before any HCL exists.

GitHub's Spec Kit gives you a real, structured template for this (`specify init` installs it as
skills inside Claude Code: `/speckit-specify`, `/speckit-plan`, `/speckit-tasks`). This project's
own spec was written straight into that template's format:

`file: lab/spec-driven/spec.md`
```
# Feature Specification: Checkout Web Tier Autoscaling

## Requirements

### Functional Requirements

- FR-001: The Auto Scaling Group's health check grace period MUST be long enough to
  survive the checkout app's real boot sequence (a `dnf install` of httpd plus service
  start on a cold instance, which can run well past a minute on a slow mirror), so a
  slow-starting-but-healthy instance is never killed as if it had failed. It must not be
  so long that a genuinely broken instance survives for minutes before being replaced.
- FR-002: Scale-in MUST prefer terminating the oldest launch template version first, so a
  mid-rollout instance running the newest code is never the one picked to die during a
  routine scale-in.
- FR-003: Capacity MUST be bounded to a known, justified peak, not an arbitrary round
  number. This tier's measured peak is 2x its steady-state baseline of 2 instances.
- FR-004: Scale-out MUST target average CPU utilization with headroom before saturation,
  and MUST set an explicit cooldown short enough to react to a real flash-sale traffic
  spike, not the provider's 5-minute default built for slower-moving workloads.
- FR-005: Instance metadata MUST require IMDSv2 tokens. IMDSv1 has no request signing and
  is a known SSRF pivot path into instance credentials.

### Constraints

- C-001: No account-specific value may be hardcoded into a resource block.
- C-002: The launch template and Auto Scaling Group must be wired together, not left as
  two independently-applied resources.

## Success Criteria

- SC-001: `health_check_grace_period` = 180
- SC-002: `termination_policies` = `["OldestLaunchTemplate", "OldestInstance", "Default"]`
- SC-003: `min_size` = 2, `max_size` = 4
- SC-004: an `aws_autoscaling_policy` of type `TargetTrackingScaling`, predefined metric
  `ASGAverageCPUUtilization`, `target_value` = 55, and the ASG's own `default_cooldown` = 90
- SC-005: the launch template's `metadata_options.http_tokens` = `"required"`
- SC-006: checkov passes `CKV_AWS_79` (IMDSv2) on the launch template, see the note below
```

Five requirements, two constraints, six success criteria, every one of them a real decision the
one-line ticket left open. The full spec is in `lab/spec-driven/spec.md`, read it end to end.

Notice SC-006 doesn't promise a fully clean `checkov` run. Keep that in mind, you'll see exactly
why in a few steps.

## Step 2: Generate against the spec

**Open** Claude Code (or Codex) in `lab/spec-driven` and give it this exact prompt:

```
claude -p "Read spec.md in this directory. Generate main.tf so every line traces back to a requirement or success criterion in the spec." \
  --permission-mode acceptEdits --allowedTools "Read,Write,Edit"
```

This is what came back, captured for real, then validated with no hand-tuning after the fact:

`file: lab/spec-driven/main.tf`
```
# data source: no hardcoded AMI id (C-001)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "checkout_web" {
  name_prefix   = "checkout-web-"
  image_id      = data.aws_ami.al2023.id # C-001: AMI resolved via data source, not hardcoded
  instance_type = "t3.micro"

  # SC-005 / FR-005: require IMDSv2 tokens (CKV_AWS_79), blocks the SSRF-to-credentials
  # pivot that IMDSv1's unsigned metadata requests allow.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "checkout_web" {
  name = "checkout-web-asg"

  # C-002: launch template wired directly into the ASG (latest version), not applied
  # independently.
  launch_template {
    id      = aws_launch_template.checkout_web.id
    version = "$Latest"
  }

  # SC-003 / FR-003: peak bounded to 2x the 2-instance steady-state baseline, not a
  # round-number guess.
  min_size = 2
  max_size = 4

  # SC-001 / FR-001: long enough to survive a cold-boot dnf install + httpd start on a
  # slow mirror, short enough that a genuinely broken instance doesn't linger for minutes.
  health_check_grace_period = 180
  health_check_type         = "EC2"

  # SC-002 / FR-002: kill the oldest launch template version first so a mid-rollout
  # instance running the newest code is never the one picked during routine scale-in.
  termination_policies = ["OldestLaunchTemplate", "OldestInstance", "Default"]

  # SC-004 / FR-004: cooldown shortened from the provider's 5-minute default so the ASG
  # can react to a real flash-sale spike.
  default_cooldown = 90

  availability_zones = ["us-east-1a"]
}

# SC-004 / FR-004: target tracking on average CPU with headroom before saturation.
resource "aws_autoscaling_policy" "checkout_web_cpu" {
  name                   = "checkout-web-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.checkout_web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 55
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

## Step 3: Answer the same ticket without a spec

**Open** a second, fresh Claude Code (or Codex) session in `lab/vibe-coded`, no spec file anywhere
in the directory, and give it only the ticket itself:

```
claude -p "Give me an autoscaling web tier for our checkout service." \
  --permission-mode acceptEdits --allowedTools "Read,Write,Edit"
```

This is what came back, captured for real, no hand-tuning:

`file: lab/vibe-coded/main.tf`
```
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "checkout_web" { # ... ingress from the ALB, egress open }
resource "aws_security_group" "checkout_alb" { # ... ingress from the internet, egress open }

resource "aws_launch_template" "checkout_web" {
  name_prefix   = "checkout-web-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.checkout_web.id]
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y httpd
    echo "checkout service ok" > /var/www/html/index.html
    systemctl enable --now httpd
  EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = { Name = "checkout-web" }
  }
}

resource "aws_lb" "checkout" { # ... }
resource "aws_lb_target_group" "checkout_web" { # ... }
resource "aws_lb_listener" "checkout_web" { # ... }

resource "aws_autoscaling_group" "checkout_web" {
  name_prefix         = "checkout-web-"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.checkout_web.arn]

  min_size         = 2
  max_size         = 6
  desired_capacity = 2

  health_check_type         = "ELB"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.checkout_web.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "checkout_web_cpu" {
  name                   = "checkout-web-target-tracking-cpu"
  autoscaling_group_name = aws_autoscaling_group.checkout_web.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}
```

That's a real, honest first pass at "give me an autoscaling web tier for our checkout service" (the
full, unabridged file is `lab/vibe-coded/main.tf`, this is trimmed here for the security groups and
load balancer boilerplate, which aren't the point). It's a competent-looking build, not a strawman:
an ALB, two security groups, a launch template with real `user_data`, an ASG, a target tracking
policy. Nobody would flag it in a five-second glance at a PR. That's exactly the danger.

## Five judgment calls, one ticket, two real answers

Both modules trace back to the same seven words. Neither is broken HCL. Read the real values,
captured straight from `terraform plan`/`terraform state show` on each module:

`file: lab/evidence/plan-diff.txt`
```
                          vibe-coded          spec-driven         driven by
health_check_grace_period 60                  180                 FR-001 / SC-001
termination_policies      (unset, AWS default) OldestLaunchTemplate, OldestInstance, Default
                                                                    FR-002 / SC-002
min_size / max_size       2 / 6               2 / 4               FR-003 / SC-003
target_value (CPU %)      60                  55                  FR-004 / SC-004
default_cooldown          (unset, 300s default) 90                FR-004 / SC-004
metadata_options.http_tokens (unset, IMDSv1 allowed) required     FR-005 / SC-005
```

Every row is a real judgment call the one-line ticket left silent. Nothing in "give me an
autoscaling web tier" says any of these numbers. The vibe-coded run picked something
plausible-looking for each one and moved on, exactly what answering a spec-less ask under a
deadline looks like. `60` seconds sounds fine until you remember `dnf install` on a cold mirror
can run past a minute by itself, at which point the ASG kills a perfectly healthy instance for
taking too long to boot, then keeps doing it, because the replacement hits the same clock.

**Observe** one more thing the diff shows that the spec never asked for: the vibe-coded run also
generated a whole ALB, two security groups, and a target group the ticket never mentioned and the
spec never required. A spec doesn't just pin down ambiguous numbers, it bounds scope too.

## Step 4: Run checkov against both

```
checkov -d lab/spec-driven --compact --quiet
```

`[ Expected output ]`
```
Passed checks: 7, Failed checks: 1, Skipped checks: 0
```

```
checkov -d lab/vibe-coded --compact --quiet
```

`[ Expected output ]`
```
Passed checks: 20, Failed checks: 14, Skipped checks: 0
```

Read both finding lists (`lab/evidence/checkov-spec-driven.txt` and `checkov-vibe-coded.txt` have
the full real output). The vibe-coded version fails `CKV_AWS_79`, IMDSv1 left reachable, exactly
what FR-005 named up front, plus nine more real findings on the ALB nobody asked for: no deletion
protection, no access logging, no WAF, HTTP instead of HTTPS, no TLS 1.2 minimum. The spec-driven
version passes `CKV_AWS_79`, exactly what SC-006 promised.

**Observe** something else, though: the spec-driven version still has 1 failed check,
`CKV_AWS_153`, the launch template's own tags. Checkov flags it because this spec's author (you)
never wrote a requirement for tags. **Why does that matter?** A spec's success criteria only cover
what someone thought to write down. That's exactly why the policy gate in M09 still runs after
this project. A spec pins down what gets generated. It doesn't replace the check that runs
afterward.

## Step 5: Apply the spec-driven module and check it against its own spec

Start Floci the usual way:

```
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0
```

**Apply** it and read the real state back against SC-001 through SC-004:

```
cd lab/spec-driven
terraform apply -auto-approve
terraform state show aws_autoscaling_group.checkout_web
```

`[ Expected output ]`
```
# aws_autoscaling_group.checkout_web:
resource "aws_autoscaling_group" "checkout_web" {
    default_cooldown                 = 90
    health_check_grace_period        = 180
    health_check_type                = "EC2"
    max_size                         = 4
    min_size                         = 2
    name                             = "checkout-web-asg"
    termination_policies             = [
        "OldestLaunchTemplate",
        "OldestInstance",
        "Default",
    ]

    launch_template {
        id      = "lt-40425f188032c576b"
        version = "$Latest"
    }
}
```

Every value in the running infrastructure matches the success criterion it was written against,
verified against the real applied state, not just the HCL that produced it.

**Destroy** it before you're done, there's nothing here worth leaving up:

```
terraform destroy -auto-approve
docker rm -f floci
```

`[ Expected output ]`
```
Destroy complete! Resources: 3 destroyed.
```

## Step 6: Apply the spec-driven module with OpenTofu

Same HCL, different binary. This is what "one language, two runtimes" actually
means: not a separate OpenTofu curriculum, one real proof that the module you just
built and verified with Terraform applies identically with OpenTofu.

**Confirm** the pinned version:

```
tofu version
```

`[ Expected output ]`
```
OpenTofu v1.12.2
on darwin_arm64
```

Step 5 tore Floci down at the end, so **start** it again the same way:

```
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0
```

You're still in `lab/spec-driven` from Step 5. Terraform left its own provider cache,
lock file, and state behind, and OpenTofu will re-resolve all three if you don't clear
them first, so your real output would carry extra provider-resolution lines that
aren't in the block below. **Clear** Terraform's leftovers, then **apply** the exact
same spec-driven module, no changes to the `.tf` files:

```
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
tofu init -backend=false -input=false
tofu apply -auto-approve
```

`[ Expected output ]`
```
OpenTofu used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

OpenTofu will perform the following actions:

  # aws_autoscaling_group.checkout_web will be created
  # aws_autoscaling_policy.checkout_web_cpu will be created
  # aws_launch_template.checkout_web will be created

Plan: 3 to add, 0 to change, 0 to destroy.
aws_launch_template.checkout_web: Creating...
aws_launch_template.checkout_web: Creation complete after 5s
aws_autoscaling_group.checkout_web: Creating...
aws_autoscaling_group.checkout_web: Creation complete after 1m12s
aws_autoscaling_policy.checkout_web_cpu: Creating...
aws_autoscaling_policy.checkout_web_cpu: Creation complete after 1s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

Same resource count as the `terraform apply` run in Step 5. **Destroy** it:

```
tofu destroy -auto-approve
docker rm -f floci
```

`[ Expected output ]`
```
Plan: 0 to add, 0 to change, 3 to destroy.
aws_autoscaling_policy.checkout_web_cpu: Destroying...
aws_autoscaling_policy.checkout_web_cpu: Destruction complete after 0s
aws_autoscaling_group.checkout_web: Destroying...
aws_autoscaling_group.checkout_web: Destruction complete after 7s
aws_launch_template.checkout_web: Destroying...
aws_launch_template.checkout_web: Destruction complete after 0s

Destroy complete! Resources: 3 destroyed.
```

Terraform is BUSL-licensed. OpenTofu is MPL-2.0, a fork maintained under the Linux
Foundation. For a module with no provider-specific Terraform-only features, which
this one is, the choice of runtime is a license and tooling decision, not a
different infrastructure outcome. That's the whole lesson, proven, not asserted.

#### Exercise

Write your own spec for a real, underspecified ask from your own backlog: requirements,
constraints, and success criteria, before you generate anything. Then generate against it, and
check the output line by line against your own criteria, not by eyeballing it. Pick something with
at least three real judgment calls, not one obvious setting, or the exercise won't teach you what
this project just did.

## Validation

Run the full check yourself, both versions, start to finish, against a real Floci container:

```
cd modules/module-07-spec-driven-infra/lab
./run.sh
```

`run.sh` checks:

- Both modules stay valid HCL: `fmt`, `init`, `validate` clean on spec-driven and vibe-coded
- The five judgment calls genuinely diverge: real `terraform plan` output compared line by line
  between the two versions
- checkov passes `CKV_AWS_79` on spec-driven, still fails `CKV_AWS_153` (the honest, unscoped gap),
  and fails both `CKV_AWS_79` and an ALB/TLS finding on vibe-coded
- `spec.md` carries all three real parts: requirements, constraints, and success criteria
- A real `terraform apply` and `destroy` of the spec-driven module against Floci, with the applied
  state checked against every success criterion

## Summary

What you built:

- A real spec, requirements, constraints, and success criteria, for an autoscaling web tier with
  five genuine ambiguities
- A module generated from that spec, every line traced back to a requirement
- The same one-line ticket answered a second time with no spec, a competent-looking build that
  was quietly wrong on all five judgment calls, plus a whole unrequested ALB
- A real, applied spec-driven module, checked against its own success criteria, then destroyed

The vibe-coded version wasn't broken, it was plausible and quietly wrong on five real decisions,
plus a whole surface area checkov found nine more problems on. The spec-driven version passed
everything tied to its own requirements and still had one honest gap outside them. A spec makes
the proposal better and bounds what gets built. It's still the pipeline, the gate in M06 and the
policy check in M09, that decides whether `apply` was ever safe to run. You'll need that spec
habit again in the capstone, where nobody hands you a one-line ticket at all.
