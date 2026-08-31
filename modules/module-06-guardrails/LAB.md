# Lab 6: Write a Hook That Actually Blocks Something

**Tier 1** · ~20 min · Docker socket mounted, `floci/floci:1.7.0` pinned, real `terraform apply`
and `destroy` against it.

M04 gave the agent a skill it could choose to reach for. That's still voluntary. This lab builds
the piece that isn't: a hook that runs on every attempted `apply`, whether or not anything asked
for it, and actually stops a dangerous plan from going through. You'll watch a delete happen with
no gate in the way, then watch the exact same delete get refused once the gate is wired in.

## Pre Requisites

- Completed M01, or at least read its `reading/concepts.md` (blast radius is defined there)
- Docker reachable at `/var/run/docker.sock`:

```
docker info
```

## The starting infrastructure

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
  bucket = "m06-lab-logs"

  tags = {
    Environment = "lab"
    Owner       = "m06-lab"
    ManagedBy   = "terraform"
  }
}
```

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

## Run 1: no gate, watch a delete just happen

**Delete** the `logs` bucket resource from `module/main.tf` (comment it out or remove the block),
then **apply** again, with nothing in the way:

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

That's it. No pause, no confirmation beyond the usual `-auto-approve`, no record of why. An agent
running unattended at a high autonomy rung with no gate would do exactly this, on your say-so or
on a misread intent, and there's nothing between the plan and the damage.

**Restore** the `logs` block and re-apply, so you're back to two buckets before the next step.

## Write the gate

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

## Run 2: the same delete, now blocked

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

Exit code 1. **Check** the bucket is still there:

```
terraform -chdir=module state list
```

`[ Expected output ]`
```
aws_s3_bucket.artifacts
aws_s3_bucket.logs
```

Same delete, same intent, same underlying `terraform apply` call. The only thing that changed is
whether a gate sat between the plan and the apply. That's the whole lesson of this module in one
before/after.

**Restore** the `logs` block once more before continuing.

## A safe change still passes

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

## A permission boundary, alongside the hook

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
transcript, that depends on the specific agent runtime enforcing it, but the mechanism is the same
shape as the hook: a rule that runs regardless of what the agent decided to do.

## Which failure was which

- The missing gate in run 1 wasn't a context problem or a skill problem. The agent (or you, by
  hand) had everything it needed to do the delete correctly. Nothing was there to say the delete
  itself was the problem
- A skill (M04) could have suggested caution. It could not have stopped the apply. Only something
  that runs regardless of the agent's choice can do that
- The resource-type and resource-count checks generalize the same idea beyond deletes: some
  changes are risky by shape, not by action type alone

## Clean up

**Reconcile** and **destroy**, the numbered step every Tier 1 lab in this course ends with:

```
terraform -chdir=module destroy -auto-approve
docker rm -f floci
```

`[ Expected output ]`
```
Plan: 0 to add, 0 to change, 3 to destroy.
aws_s3_bucket.artifacts: Destruction complete after 0s
aws_s3_bucket.logs: Destruction complete after 0s
aws_s3_bucket.docs: Destruction complete after 0s

Destroy complete! Resources: 3 destroyed.
```

#### Exercise

Set `MAX_RESOURCES=1` and try to apply the `docs` bucket addition together with one more new
bucket in the same plan. Then try touching an `aws_iam_role`. Write two lines in `notes.md`: which
of the three policies (delete, count, type) would your own team's worst past incident have
tripped, and would a human have caught it faster than the gate did?

#### Summary

You watched an ungated delete happen with nothing stopping it, then watched the identical delete
get refused once a hook sat between the plan and the apply. A skill can only ever suggest. A hook
runs regardless. That's the whole difference between M04 and this module, made concrete against a
real Floci-backed bucket. M08 picks this up and generalizes it into a full harness, and M09 puts
real cloud-shaped scanners in front of the same gate.

##### Reading List

- `reading/concepts.md` in this module: the voluntary-vs-enforced distinction and the
  blast-radius-from-plan-json mechanism
- `reading/concepts.md` in M01: no undo, state, blast radius, silent failure
- [Terraform: the `terraform show -json` plan representation](https://developer.hashicorp.com/terraform/internals/json-format)

##### Search Keywords

- hook, pre-apply gate, permission boundary
- blast radius, terraform plan -json, terraform show -json
- gate vs warning, exit code contract
- floci, Tier 1 lab, apply, destroy

##### Re-verify

`lab/run.sh` runs the whole sequence for real: baseline apply, an ungated delete that succeeds, the
same delete blocked by the gate, a safe change that passes, a high-radius type blocked, an
oversized batch blocked, then reconcile and destroy, all against a real Floci container. Run it
whenever the pinned Floci or Terraform versions in this lab get bumped:

```
cd modules/module-06-guardrails/lab
./run.sh
```
