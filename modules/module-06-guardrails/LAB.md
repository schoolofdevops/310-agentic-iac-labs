# Project 06: Guard a Real Delete Using a Hook and a Plan-Approve-Apply Harness

**Tier 1** · ~40 min · Docker socket mounted, `floci/floci:1.7.0` pinned, real `terraform apply`
and `destroy` against it, real Claude Code sessions in `--permission-mode plan`.

In this project, you will build two independent guardrails around one small, real storage
system, two S3 buckets, one of them holding a genuine log file that an agent could delete for
good with a single misread instruction. You will test both guardrails against the exact same
real delete, so you can see, on the same object, what each one costs and what each one actually
stops.

**What you're building, at a glance:**

- A real delete, run with nothing in the way, that destroys a real log file for good
- `hooks/blast_radius_gate.sh`, a **mechanical gate** that reads a real Terraform plan and
  refuses a real delete
- The exact same delete, run again, now blocked by that gate
- A permission-boundary config that denies an agent's write tools on a path, before a plan
  even exists
- `harness/{propose,approve,apply_with_approval}.sh`, a **plan-review-approve-apply harness**
  you build yourself, wrapping the real `--permission-mode plan` mechanic from M02 into a
  formal propose-then-approve workflow, with a real human approval step that blocks apply
  until it exists

## Pre Requisites

- Completed M01, or at least read its `reading/concepts.md` (blast radius is defined there)
- Docker reachable at `/var/run/docker.sock`:

```
docker info
```

## Stage 1: Block a dangerous delete with a mechanical gate

### Step 1: Set up the starting infrastructure

`file: lab/module/main.tf`
```
resource "aws_s3_bucket" "artifacts" {
  bucket = "m06-lab-artifacts"

  tags = {
    Environment = "lab"
    Owner       = "m06-lab"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket        = "m06-lab-logs"
  force_destroy = true

  tags = {
    Environment = "lab"
    Owner       = "m06-lab"
    ManagedBy   = "terraform"
  }
}
```

`force_destroy = true` is doing real work here, and it's realistic, not a contrived flag added
just for this lab. Without it, deleting a bucket that still has objects in it fails outright: real
AWS, and Floci behind it, both refuse with `BucketNotEmpty`. That refusal is itself a small
guardrail, the provider's own. A lot of teams turn `force_destroy` on precisely to stop that error
from failing CI, and the moment they do, the provider's own guardrail is gone. What's left to
stand between an agent and a real object being destroyed for good is exactly what this lab builds.

**Copy** the lab into a scratch directory and **start** Floci, same Tier 1 setup every lab in
this course uses:

```
cp -r modules/module-06-guardrails/lab ~/m06-lab
cd ~/m06-lab
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0
```

**Apply** the baseline:

```
terraform -chdir=module init -backend=false
terraform -chdir=module apply -auto-approve
```

`[ Expected output ]`
```
Plan: 2 to add, 0 to change, 0 to destroy.
aws_s3_bucket.artifacts: Creating...
aws_s3_bucket.logs: Creating...
aws_s3_bucket.artifacts: Creation complete after 0s [id=m06-lab-artifacts]
aws_s3_bucket.logs: Creation complete after 0s [id=m06-lab-logs]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Two real buckets, in a real backend container, same as M04.

### Step 2: Watch an ungated delete destroy real data

An empty bucket getting deleted is easy to shrug off. **Put** something real in it first:

```
echo "2026-08-30 03:14:02 auth-service ERROR db timeout after 30s, retrying" > /tmp/app.log
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url http://localhost:4566 \
  s3 cp /tmp/app.log s3://m06-lab-logs/2026-08-30/app.log
```

That's a real object, in a real bucket, in the real Floci container. Now **delete** the `logs`
bucket resource from `module/main.tf` (comment it out or remove the block), and **apply** again,
with nothing in the way:

```
terraform -chdir=module apply -auto-approve
```

`[ Expected output ]`
```
  # aws_s3_bucket.logs will be destroyed

Plan: 0 to add, 0 to change, 1 to destroy.
aws_s3_bucket.logs: Destroying... [id=m06-lab-logs]
aws_s3_bucket.logs: Destruction complete after 0s

Apply complete! Resources: 0 added, 0 changed, 1 destroyed.
```

**Check** what's left of the object:

```
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url http://localhost:4566 \
  s3 ls s3://m06-lab-logs/2026-08-30/
```

`[ Expected output ]`
```
An error occurred (NoSuchBucket) when calling the ListObjectsV2 operation: The specified bucket does not exist.
```

Not "moved to a recycle bin," not "recoverable within 30 days." The bucket and the log line inside
it are both just gone. No pause, no confirmation beyond the usual `-auto-approve`, no record of
why. An agent running unattended at a high autonomy step with no gate would do exactly this, on
your say-so or on a misread intent, and there's nothing between the plan and the damage.

**Restore** the `logs` block, re-apply, and re-upload the object, so you're back to where you
started before the next step:

```
terraform -chdir=module apply -auto-approve
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url http://localhost:4566 \
  s3 cp /tmp/app.log s3://m06-lab-logs/2026-08-30/app.log
```

### Step 3: Write the gate

**Write** the piece that was missing: a script that reads a real `terraform plan`, in JSON, and
decides whether it's safe to apply at all.

`file: hooks/blast_radius_gate.sh`
```
#!/usr/bin/env bash
set -uo pipefail
PLAN_JSON="${1:?usage: blast_radius_gate.sh <plan.json>}"
MAX_RESOURCES="${MAX_RESOURCES:-5}"
BLOCK_ON_DELETE="${BLOCK_ON_DELETE:-1}"
HIGH_RADIUS_TYPES="${HIGH_RADIUS_TYPES:-aws_vpc,aws_iam_policy,aws_iam_role}"

TOTAL=$(jq '[.resource_changes[] | select(.change.actions != ["no-op"])] | length' "$PLAN_JSON")
DELETES=$(jq '[.resource_changes[] | select(.change.actions | index("delete"))] | length' "$PLAN_JSON")

if [ "$BLOCK_ON_DELETE" = "1" ] && [ "$DELETES" -gt 0 ]; then
  echo "BLOCKED: ${DELETES} delete action(s) in this plan." >&2
  exit 1
fi
if [ "$TOTAL" -gt "$MAX_RESOURCES" ]; then
  echo "BLOCKED: ${TOTAL} resource changes exceeds max-resources ${MAX_RESOURCES}." >&2
  exit 1
fi
IFS=',' read -ra TYPES <<< "$HIGH_RADIUS_TYPES"
for t in "${TYPES[@]}"; do
  HIT=$(jq --arg t "$t" '[.resource_changes[] | select(.type == $t) | select(.change.actions != ["no-op"])] | length' "$PLAN_JSON")
  [ "$HIT" -gt 0 ] && { echo "BLOCKED: touches high-radius type '${t}'." >&2; exit 1; }
done
exit 0
```

Three policies, in order: block any delete, block a batch over `MAX_RESOURCES` (default 5), block
a change to a resource type on the high-radius list (`aws_vpc`, `aws_iam_policy`, `aws_iam_role` by
default). Exit 0 means safe to apply. Exit non-zero means refuse. `hooks/apply_with_gate.sh` wraps
`terraform plan` → `terraform show -json` → this script → `terraform apply`, in that order, and
never reaches `apply` if the gate exits non-zero.

### Step 4: Watch the same delete get blocked

**Delete** the same `logs` bucket block again. This time, **apply** through the gate instead of
directly:

```
./hooks/apply_with_gate.sh
```

`[ Expected output ]`
```
==> gate: 1 resource change(s), 1 delete(s), max allowed 5
BLOCKED: 1 delete action(s) in this plan. block-on-delete is on.
  - delete: aws_s3_bucket.logs
apply refused: gate blocked this plan.
```

Exit code 1. **Check** the bucket, and the object inside it, are still there:

```
terraform -chdir=module state list
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url http://localhost:4566 \
  s3 ls s3://m06-lab-logs/2026-08-30/
```

`[ Expected output ]`
```
aws_s3_bucket.artifacts
aws_s3_bucket.logs
2026-09-01 17:18:13         70 app.log
```

Same delete, same real object at risk, same underlying `terraform apply` call. The only thing
that changed is whether a gate sat between the plan and the apply. That's the whole lesson of
mechanism one, in one before/after: the same `force_destroy = true` bucket, the same auth-service
log line, destroyed for good in run 1, still there in run 2.

**Restore** the `logs` block once more before continuing.

### Step 5: Confirm a safe change still passes

Not every gate is a wall. **Add** a small, non-destructive change, a new bucket:

`edit file: module/main.tf`
```
resource "aws_s3_bucket" "docs" {
  bucket = "m06-lab-docs"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}
```

```
./hooks/apply_with_gate.sh
```

`[ Expected output ]`
```
==> gate: 1 resource change(s), 0 delete(s), max allowed 5
    ok, gate passes
aws_s3_bucket.docs: Creating...
aws_s3_bucket.docs: Creation complete after 0s [id=m06-lab-docs]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

No delete, under the resource-count limit, no high-radius type. The gate isn't there to say no to
everything, it's there to say no to the specific things that make infrastructure mistakes worse
than application-code mistakes: no undo, blast radius, silent failure, the three properties from
M01's reading.

### Step 6: Add a permission boundary alongside the hook

A hook decides whether a proposed *change* is safe. A permission boundary decides what the agent
can even touch in the first place, before a plan exists at all. In this repo that's a Claude Code
settings file, not a Terraform concept:

`file: .claude/settings.local.example.json`
```
{
  "permissions": {
    "deny": [
      "Write(shared/**)",
      "Edit(shared/**)"
    ]
  }
}
```

This is a config-level guardrail: the agent's write tools are denied on anything under `shared/`,
enforced by the harness before the agent ever gets a chance to propose a change there, the same
way the gate above is enforced before `apply`. This lab doesn't stage a live denied-write
transcript, that depends on the specific agent runtime enforcing it, but the mechanism works the
same way as the hook: a rule that runs regardless of what the agent decided to do.

## A second guardrail: take apply access away entirely

The gate above answers "is this specific plan safe?" every single time, correctly, but it's still
sitting downstream of a system where the agent has `apply` access at all. There's a structurally
different guardrail: take that access away entirely. An agent never runs `terraform apply` against
anything real. It opens a PR instead. The PR runs through the same kind of checks this module just
built, an automated review, a human merges it, and a separate GitOps controller, reconciling
against the merged state of the repo, is the only thing that ever touches the real infrastructure.
"Can this agent apply?" stops being a question the gate has to answer correctly every time, because
the agent was never wired to `apply` in the first place. This is a different kind of guardrail from
the gate above, structural instead of mechanical. Building it for real, with a real GitOps
controller reconciling a real merged PR, is M11's job, not this project's. Two options: gate the
change, or remove the ability to make it unreviewed.

## Stage 2: Build a plan-review-approve-apply harness

The gate blocks based on what a plan contains. It doesn't know who's asking, and it doesn't pause
for a human to actually read the reasoning before something happens. M02 already showed you the
real building block this needs: `claude --permission-mode plan` proposes a change and writes
nothing, an agent hands you a plan document instead of a fait accompli. This stage turns that one
flag into a small, real harness with four steps, and an explicit refusal wired into the middle of
it.

### Step 1: Propose a change and save the plan

`file: harness/propose.sh` (step a and b: a real agent proposes, a real plan gets saved)
```
#!/usr/bin/env bash
set -uo pipefail
ASK="${1:?usage: propose.sh \"<intent>\"}"
cd "$(dirname "$0")/.."

BEFORE=$(date +%s)
claude -p "${ASK} Propose the exact HCL to add to module/main.tf. Do not write any files, this is a proposal only." \
  --permission-mode plan
...
cp "$LATEST" "plans/${SLUG}"
echo "PLAN_SAVED: plans/${SLUG}"
```

**Run** it against a real ask:

```
cd modules/module-06-guardrails/lab
./harness/propose.sh "Add a new S3 bucket resource named 'audit' with bucket name 'm06-lab-audit'."
```

`[ Expected output ]`
```
**Proposed HCL**, append to `module/main.tf`:

resource "aws_s3_bucket" "audit" {
  bucket = "m06-lab-audit"
  ...
}

PLAN_SAVED: plans/add-a-new-s3-squishy-metcalfe.md
```

Plan mode really did write nothing. `module/main.tf` is untouched. What exists now is a plan file,
under `plans/`, the same real artifact `--permission-mode plan` produces in M02, just copied
somewhere your team can actually review it instead of a hidden home-directory path. Your filename
will differ, plan mode's naming isn't deterministic, the pattern is what matters.

### Step 2: Try to apply without approval

**Try** applying it anyway, before anyone approved it:

```
./harness/apply_with_approval.sh plans/add-a-new-s3-squishy-metcalfe.md
```

`[ Expected output ]`
```
REFUSED: plans/add-a-new-s3-squishy-metcalfe.md has not been approved. Run harness/approve.sh first.
```

Exit code 1, `module/main.tf` still untouched.

### Step 3: Approve the plan

The human gate is not optional and not implicit, it's a file that has to exist:

`file: harness/approve.sh`
```
#!/usr/bin/env bash
set -uo pipefail
PLAN="${1:?usage: approve.sh plans/<file>.md}"
cd "$(dirname "$0")/.."
[ -f "$PLAN" ] || { echo "REFUSED: no such plan file: $PLAN" >&2; exit 1; }
APPROVER="${APPROVER:-$(whoami)}"
{
  echo "approved-by: ${APPROVER}"
  echo "approved-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "approved-plan: ${PLAN}"
} > "${PLAN}.approved"
echo "APPROVED: ${PLAN} (by ${APPROVER})"
```

**Approve** it, for real, as yourself:

```
./harness/approve.sh plans/add-a-new-s3-squishy-metcalfe.md
```

`[ Expected output ]`
```
APPROVED: plans/add-a-new-s3-squishy-metcalfe.md (by gshah)
```

### Step 4: Apply the approved plan

**Apply** it now that the approval marker exists. This is the second real invocation, the only
one allowed to touch a file:

```
./harness/apply_with_approval.sh plans/add-a-new-s3-squishy-metcalfe.md
```

`[ Expected output ]`
```
==> approval found: approved-by: gshah approved-at: 2026-09-01T11:42:04Z approved-plan: plans/add-a-new-s3-squishy-metcalfe.md
Done. `audit` bucket added, matches plan exact.
==> agent edited module/main.tf per the approved plan, now running the mechanical gate before any real apply
==> gate: 1 resource change(s), 0 delete(s), max allowed 5
    ok, gate passes
aws_s3_bucket.audit: Creating...
aws_s3_bucket.audit: Creation complete after 0s [id=m06-lab-audit]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

A second, fresh Claude Code session read the approved plan and edited `module/main.tf` to match
it, nothing more, then this module's own `apply_with_gate.sh`, the mechanism you built first,
still ran before Terraform touched anything real. Two independent guardrails stacked on the same
apply: one asks who approved this, one asks what this plan actually contains. Neither one trusts
the other to have caught everything.

**Check** the state:

```
terraform -chdir=module state list
```

`[ Expected output ]`
```
aws_s3_bucket.artifacts
aws_s3_bucket.docs
aws_s3_bucket.logs
aws_s3_bucket.audit
```

## Which failure was which

- The missing gate in run 1 wasn't a context problem or a skill problem. The agent (or you, by
  hand) had everything it needed to do the delete correctly. Nothing was there to say the delete
  itself was the problem, and a real object was gone for good because of it
- A skill (M04) could have suggested caution. It could not have stopped the apply. Only something
  that runs regardless of the agent's choice can do that
- The resource-type and resource-count checks generalize the same idea beyond deletes: some
  changes are risky by kind, not by action type alone
- The structural guardrail doesn't try to out-think every dangerous plan, it just removes the
  agent's ability to apply anything unreviewed in the first place. Different failure mode,
  different fix
- The approval harness doesn't replace the gate, it adds a second, independent question in
  front of it: is this plan safe, versus did a specific human actually say yes to this specific
  plan. The harness refused before approval existed, no matter how safe the plan looked

## Clean up

**Reconcile** and **destroy**, the numbered step every Tier 1 lab in this course ends with:

```
terraform -chdir=module destroy -auto-approve
docker rm -f floci
```

`[ Expected output ]`
```
Plan: 0 to add, 0 to change, 4 to destroy.
aws_s3_bucket.artifacts: Destruction complete after 0s
aws_s3_bucket.logs: Destruction complete after 0s
aws_s3_bucket.docs: Destruction complete after 0s
aws_s3_bucket.audit: Destruction complete after 0s

Destroy complete! Resources: 4 destroyed.
```

#### Exercise

Set `MAX_RESOURCES=1` and try to apply the `docs` bucket addition together with one more new
bucket in the same plan. Then try touching an `aws_iam_role`. Write two lines in `notes.md`: which
of the three policies (delete, count, type) would your own team's worst past incident have
tripped, and would a human have caught it faster than the gate did?

Then try to break the harness: run `harness/propose.sh` for a plan that deletes the `logs` bucket,
approve it with `harness/approve.sh`, and apply it. Does the mechanical gate from mechanism one
still block it, even though a human already approved it? What does that tell you about which
guardrail should run last?

## Validation

Run the whole sequence yourself, both guardrails, start to finish, against a real Floci
container. This is what catches a regression if the pinned Floci or Terraform versions in this
project ever get bumped:

```
cd modules/module-06-guardrails/lab
./run.sh
```

`run.sh` checks:

- Baseline apply, then an ungated delete that destroys a real object
- The same delete, blocked by the gate, plus a safe change that still passes, a high-radius
  type blocked, and an oversized batch blocked
- The full propose-approve-apply harness against a real Claude Code session
- Reconcile and destroy, all against the real Floci container

## Summary

What you built:

- A real delete that destroyed a real log file for good, with nothing in the way
- `hooks/blast_radius_gate.sh`, a mechanical gate that reads a real Terraform plan and refuses
  a real delete, a batch over size, or a high-radius resource type
- The identical delete, run again, refused by that gate
- A permission-boundary config that denies an agent's write tools on a path before a plan
  exists
- `harness/{propose,approve,apply_with_approval}.sh`, a real plan-review-approve-apply
  harness: a session proposes, a file gets saved, an approval step blocks apply until a human
  says yes, and a second session applies exactly what was approved, still through the
  mechanical gate

A skill can only ever suggest. A hook runs regardless. Take `hooks/blast_radius_gate.sh` and the
`harness/` scripts with you, they're generic to any Terraform plan, not specific to this
project's buckets. M08 picks this up and generalizes it into a full harness, and M09 puts real
cloud scanners in front of the same gate.
