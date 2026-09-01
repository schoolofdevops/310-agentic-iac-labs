# Lab 12: Write a Real Stopping Condition, Wire a Real Trigger

**Tier 0** · ~15 min · no cloud, no cluster, no new account. Reuses the same small Terraform
module shape from Lab 1, this time run under a loop instead of by hand.

Every earlier lab in this course, you ran once. This one you run **three times**, on purpose,
and you'll watch it behave differently each time: continue, stop, then stop again and do
nothing, because it's already done. That's the whole point of a stopping condition, it has to
be checkable by a machine, not just "looks done" to a human.

## Pre Requisites

- `terraform` and `checkov`, same as every earlier Tier 0/1 lab in this course
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

Same shape as Lab 1's starter, the same hardcoded key, on purpose. This time you're not fixing
it by hand. You're writing a loop that fixes it.

## Write the stopping condition

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

Read the check. `checkov -d .` on the current working copy, and its exit code, nothing else.
No "does this look right." An exit code either is 0 or it isn't.

**Try it once**, from a fresh copy:

```
bash lab/solution/loop.sh /tmp/m12-try
```

`[ Expected output ]`
```
CONTINUE: stopping condition not met yet, checkov still failing
```

Exactly what you'd expect. The starter still has the hardcoded key. The loop noticed, and said
so, in a form a machine (not just you) can act on.

## Give it something to do when it continues

A loop that only reports "not done yet" isn't useful on its own, something has to act on that
report. In a real setup that's an agent, at step 5 or step 6 depending on how much you trust
it. For this lab, wire in the exact fix you already know from Lab 1, real code, applied for
real when the condition isn't met:

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

## Run it three times, watch it change state each time

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
That third run is the one people forget to test. A trigger that fires after the work is
already done should notice that immediately and do nothing, not re-run the fix, not error out.
`echo $?` after each run: `1`, then `0`, then `0`.

## Wire a real trigger

The loop only runs when something re-invokes it. Here's a real one, a GitHub Actions
`schedule:` trigger, exactly the shape you'd commit to `.github/workflows/` in a real repo:

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
answer from Lab 1's exercise.

#### Summary

You wrote a real stopping condition, a script with one exact, checkable answer, and watched it
behave three different ways across three identical invocations: continue and fix, stop, stay
stopped. You wired a real trigger next to it. That's the whole loop layer, the third one from
module one, closed. Every earlier module built context or harness. This lab is the one that
finally runs one of them on its own, on a schedule, and knows when to quit.

##### Reading List

- [GitHub Actions: schedule events](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule)
- `reading/concepts.md` in this module: the full argument for why a stopping condition has to
  be exact, and what step 6 requires before it's safe

##### Search Keywords

- stopping condition, loop trigger
- GitHub Actions schedule, cron
- step 6, unattended
- idempotent re-trigger
