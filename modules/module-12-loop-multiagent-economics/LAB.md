# Project 12: Build a Self-Healing Compliance Loop With a GitHub Actions Trigger

**Tier 0** · ~15 min · no cloud, no cluster, no new account. Reuses the same small Terraform
module from Project 01, this time run under a loop instead of by hand.

In this project, you will build a small unattended loop: a script that checks one exact
condition, fixes it if it isn't met, and does nothing once it already is. Then you will wire
that same script behind a real GitHub Actions `schedule:` trigger, so it runs on its own, no
human watching it.

**What you're building, at a glance:**

- A stopping-condition script that checks exactly one thing: does `checkov` exit 0
- A real fix, applied automatically the moment the condition isn't met: a hardcoded secret
  pulled out of a Terraform variable
- Three real runs against the same working copy, three different outcomes: continue-and-fix,
  stop, stay stopped
- A real GitHub Actions `schedule:` trigger, exactly what you'd commit to a real repo

## Pre Requisites

- `terraform` and `checkov`, same as every earlier Tier 0/1 project in this course
- `python3` and `PyYAML` (already available in the devcontainer) to validate the trigger config

## The starter module

`file: modules/module-12-loop-multiagent-economics/lab/starter/main.tf`
```
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships access logs to S3"
  type        = string
  default     = "AKIAABCDEFGHIJKLMNOP"
}

resource "local_file" "log_shipper_env" {
  filename = "${path.module}/rendered/log-shipper.env"
  content  = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
}
```

Same starter as Project 01's, the same hardcoded key, on purpose. This time you are not fixing
it by hand. You are writing a loop that fixes it.

## Step 1: Write the stopping condition

A real stopping condition is a script that answers exactly one question: has the target state
been reached, yes or no, checkably. Here's the whole thing:

`file: lab/solution/loop.sh`
```
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${1:-$HERE/work}"

if [ ! -d "$WORK_DIR" ]; then
  cp -r "$HERE/../starter" "$WORK_DIR"
fi

cd "$WORK_DIR"
terraform init -backend=false -input=false -no-color >/dev/null 2>&1
CHECKOV_OUT=$(checkov -d . --compact --quiet 2>&1)
CHECKOV_CODE=$?

if [ "$CHECKOV_CODE" -eq 0 ]; then
  echo "STOPPED: stopping condition met, checkov exits 0"
  exit 0
fi

echo "CONTINUE: stopping condition not met yet, checkov still failing"
```

Read the check. `checkov -d .` on the current working copy, and its exit code, nothing else. An
exit code either is 0 or it isn't. A human deciding something "looks done" doesn't enter into it.

**Run it once**, from a fresh copy:

```
bash lab/solution/loop.sh /tmp/m12-try
```

`[ Expected output ]`
```
CONTINUE: stopping condition not met yet, checkov still failing
```

Exactly what you'd expect. The starter still has the hardcoded key. The loop noticed, and said
so, in a form a machine can act on.

## Step 2: Give the loop something to do when it continues

A loop that only reports "not done yet" needs something to act on that report. In a real setup
that's an agent, gated by the plan-review-approve-apply harness M06 built. For this project,
wire in the exact fix you already know from Project 01, real code, applied for real when the
condition isn't met:

`edit file: lab/solution/loop.sh`
```
echo "CONTINUE: stopping condition not met yet, checkov still failing"
if grep -q 'default     = "AKIA' main.tf 2>/dev/null; then
  python3 -c "
h = open('main.tf').read()
h = h.replace('  default     = \"AKIAABCDEFGHIJKLMNOP\"\n', '  sensitive   = true\n')
open('main.tf','w').write(h)
"
  echo "  (applied the real fix: pulled the hardcoded key, marked the variable sensitive)"
fi
exit 1
```

## Step 3: Run it three times, watch it change state each time

The same command you already ran, run again against the **same** working copy this time,
`solution/work` instead of a throwaway `/tmp` path:

```
rm -rf lab/solution/work
bash lab/solution/loop.sh lab/solution/work
```

`[ Expected output ]`
```
CONTINUE: stopping condition not met yet, checkov still failing
  (applied the real fix: pulled the hardcoded key, marked the variable sensitive)
```

Run **the exact same command again**, no other change:

```
bash lab/solution/loop.sh lab/solution/work
```

`[ Expected output ]`
```
STOPPED: stopping condition met, checkov exits 0
```

Run it a **third** time:

```
bash lab/solution/loop.sh lab/solution/work
```

`[ Expected output ]`
```
STOPPED: stopping condition met, checkov exits 0
```

Same command, three real runs, three different outcomes: continue-and-fix, stop, stop-again.
That third run is the one people forget to test. A trigger that fires after the work is already
done should notice that immediately and do nothing, not re-run the fix, not error out.
`echo $?` after each run: `1`, then `0`, then `0`.

## Step 4: Wire a real trigger

The loop only runs when something re-invokes it. Here's a real one, a GitHub Actions
`schedule:` trigger, exactly what you'd commit to `.github/workflows/` in a real repo:

`file: lab/solution/trigger-workflow.example.yml`
```
name: m12-loop-trigger-example
on:
  schedule:
    - cron: "0 2 * * *"
  workflow_dispatch: {}
jobs:
  run-loop:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: run the stopping-condition loop once
        run: bash lab/solution/loop.sh work
```

`0 2 * * *`, every night at two in the morning. `workflow_dispatch` alongside it, so you can
also fire it by hand while you're testing, without waiting for 2am to prove it works.

#### Exercise

Write the two-line escalation note this module's reading asked for:

- If this loop ran every night for a month and never once printed `STOPPED`, who finds out, and
  how fast?
- What's the one thing that would tell you the stopping condition itself is broken, not just
  slow?

There's no wrong answer. Keep the note, the capstone asks you to compare it against your own
answer from Project 01's exercise.

## Validation

Run the full check yourself, all three outcomes, plus the trigger config itself:

```
cd modules/module-12-loop-multiagent-economics/lab
./run.sh
```

`run.sh` checks:

- The trigger config is a real, valid cron expression with `workflow_dispatch` alongside it
- Run 1 prints `CONTINUE` and applies the real fix
- Run 2, same working copy, prints `STOPPED`
- Run 3, same working copy again, is still `STOPPED`, proving the loop is idempotent

## Summary

What you built:

- A stopping-condition script with exactly one checkable question: does `checkov` exit 0
- A real fix, applied automatically, not by hand
- Three real runs proving three states: continue-and-fix, stop, stay stopped
- A real GitHub Actions `schedule:` trigger, ready to commit to a real repo

That's the loop layer, the third one from Module 1, closed. Every earlier module built context
or harness. This project is the one that finally runs one of them on its own, on a schedule,
and knows when to quit.
