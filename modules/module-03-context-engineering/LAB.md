# Lab 3: Give the Agent What a New Hire Would Get

**Tier 0 → 1** · ~15 min · your own agent (Claude Code or Codex), the same
`terraform` and `checkov` from M01.

**The project:** a small, real Terraform module, one `docker` container running
nginx, serving a static page you control, with a sidecar credential for
shipping its access logs to S3. You will build this exact module three times
in this lab, first to measure what a noisy scan actually costs you, then twice
more to prove two separate claims about context engineering on the same code.
By the end you will have a working module and three pieces of evidence, not
just three exercises.

M01 had you run a generate-verify-fix loop by hand. This lab covers all three
disciplines from `reading/concepts.md`: **Reduce**, filtering noisy tool output
before it enters the window; **Retain**, standing facts that survive a session
reset; **Route**, a plan written to disk so a session with zero memory can pick
it up correctly. Each discipline gets its own stage below, building on the
same module.

## Pre Requisites

- Completed M01's lab, or at least read `reading/concepts.md` for that module.
  This lab reuses M01's exact one-line intent.
- An agent you can prompt directly, Claude Code or Codex, from a terminal in a
  scratch directory.

## Stage 1, Reduce: measure it yourself

Before touching an agent at all, **measure** what a raw tool call actually
costs versus a filtered one. This stage needs more real findings than the
nginx module alone would produce, so it borrows a bigger, already-real module:
the 21-resource one from `labs/shared/floci-spike`, this course's own Tier 1
spike. You will come back to your own nginx module for stages 2 and 3.

```
cd labs/shared/floci-spike
checkov -d . --framework terraform > /tmp/verbose.txt
checkov -d . --framework terraform --compact --quiet > /tmp/compact.txt
wc -c /tmp/verbose.txt /tmp/compact.txt
```

`[ Expected output shape ]`
```
   25605 /tmp/verbose.txt
    3881 /tmp/compact.txt
```

Same scan, same 25 findings. The only difference is whether every passed check
and every repeated source-code excerpt got printed too. That's an ~85%
reduction from one flag. **Read** `/tmp/verbose.txt` and count how many lines
you'd actually act on versus how many you'd just scroll past. That gap is
exactly what Reduce removes before it ever reaches an agent's context window.

## Back to your own module: the intent

Here is the module you are actually building, read the way an agent would:

> Give me a local nginx container for testing, serving a static page I control,
> with its rendered HTML kept on disk so I can diff it in git. No secrets in the
> container. I don't need it exposed outside this machine.

## Stage 2, Retain: the AGENTS.md exercise

Now the standing-context discipline: build this exact module twice from the
same intent, once with nothing written down, once with a real `AGENTS.md` in
place, and read the difference for yourself.

### Run 1: no context

**Copy** the no-context starter into a scratch directory and hand your own
agent this exact intent, in a folder with nothing else in it:

```
cp -r modules/module-03-context-engineering/lab/starter ~/m03-run1
cd ~/m03-run1
```

`file: ~/m03-run1/main.tf`
```
variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships nginx access logs to S3"
  type        = string
  default     = "AKIAABCDEFGHIJKLMNOP"
}
```

This is what came back with no `AGENTS.md` anywhere in the folder, this
module's captured, real run. **Scan** it:

```
terraform fmt -check
terraform init -backend=false && terraform validate
checkov -d .
```

`[ Expected output ]`
```
Success! The configuration is valid.

Check: CKV_SECRET_2: "AWS Access Key"
	FAILED for resource: abac545fc3bf803134bc8f78fb6160a5c6a87b26
	File: /main.tf:32-33
```

`Exit code 1`. Same finding as M01, on purpose. Nothing here is invalid
Terraform. It's legal, it's readable, it just carries a convention nobody
wrote down: secrets never get a `default`.

### Write the context

Now **write** the file that was missing. This is the actual deliverable of
this lab, not a formality:

`file: ~/m03-run1/AGENTS.md`
```
# AGENTS.md, m03-lab

Standing context for this repo. Read this before writing or changing any Terraform here.

## Provider pins

- `docker` provider: `kreuzwerker/docker`, `~> 3.0`
- `local` provider: `hashicorp/local`, `~> 2.5`

Do not upgrade a pin without a reason stated in the commit message.

## Naming convention

Resource names: `m03-lab-<purpose>`, lowercase, hyphenated. Example:
`m03-lab-site`, not `site` or `my_container`.

## Module boundaries

This is a single-purpose module: one nginx container, its rendered HTML, and one
sidecar credential. Do not add unrelated resources here.

## Never do

- Never put a secret in a `default`. Every credential-shaped variable is
  `sensitive = true`, with no default, set via `TF_VAR_<name>` at runtime.
- Never run `terraform apply` before `terraform plan` has been read by a human.

## Where secrets come from

Environment variables only, `TF_VAR_log_shipper_key` for this module. Never a
hardcoded string, never a `.tfvars` file checked into git.
```

Keep it short. A file nobody reads is worse than no file at all.

### Run 2: with context

`cp` a fresh copy of the starter next to your new `AGENTS.md`, and hand your
agent the **exact same intent** again, in a folder that now has that file in
it:

```
cp -r modules/module-03-context-engineering/lab/starter ~/m03-run2
cp ~/m03-run1/AGENTS.md ~/m03-run2/AGENTS.md
cd ~/m03-run2
```

This module's captured, real run 2 is `lab/solution/main.tf`, produced with
`lab/solution/AGENTS.md` in place:

`file: lab/solution/main.tf`
```
variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships nginx access logs to S3. Set via TF_VAR_log_shipper_key, never a default."
  type        = string
  sensitive   = true
}
```

**Re-run** the same scan:

```
terraform fmt -check
terraform init -backend=false && terraform validate
checkov -d .
```

`[ Expected output ]`
```
Exit code: 0
```

Same intent. Same agent. Same repo, minus one file. That's the whole lesson of
this lab in one diff.

### Diff the two runs

**Compare** `lab/starter/main.tf` against `lab/solution/main.tf` yourself:

```
diff -u modules/module-03-context-engineering/lab/starter/main.tf \
        modules/module-03-context-engineering/lab/solution/main.tf
```

`[ Expected output ]`
```
--- modules/module-03-context-engineering/lab/starter/main.tf
+++ modules/module-03-context-engineering/lab/solution/main.tf
@@ -17,9 +17,9 @@
 provider "docker" {}
 
 variable "log_shipper_key" {
-  description = "AWS key for the sidecar that ships nginx access logs to S3"
+  description = "AWS key for the sidecar that ships nginx access logs to S3. Set via TF_VAR_log_shipper_key, never a default."
   type        = string
-  default     = "AKIAABCDEFGHIJKLMNOP"
+  sensitive   = true
 }
 
 resource "local_file" "index_html" {
```

One variable block. That's the entire cost of writing `AGENTS.md` down once,
against the entire cost of a scanner catching a real credential in source
control after the fact. Notice which one you'd rather be doing every day.

## Stage 3, Route: prove it yourself

Retain proved that standing facts survive a reset. This stage proves the
harder claim on the same module: an in-progress plan can survive one too, as
long as it never lived only in the conversation. The finding you are about to
hand off is the exact one Retain's run 1 uncovered, the hardcoded secret, now
picked up mid-fix by a session that never saw run 1 happen.

**Write** a state file for an in-progress task, a real decision plus a real
next action, not a vague TODO:

```
mkdir -p ~/m03-route && cd ~/m03-route
cp modules/module-03-context-engineering/lab/starter/main.tf .
```

`file: ~/m03-route/STATE.md`
```
## Where this stands
main.tf has one open finding: var.log_shipper_key carries a hardcoded default.
Checkov has not been re-run since the finding was found.

## Decision already made, do not re-litigate
We are NOT deleting the variable. The fix is: drop the default, add
sensitive = true, set via TF_VAR_log_shipper_key at deploy time.

## Next action
Edit main.tf: remove the default, add sensitive = true. Run checkov -d . and
confirm exit 0.
```

**Close that terminal, or open a brand new one.** The point only holds if the
next command starts with genuinely zero memory of what you just did:

```
cd ~/m03-route
claude -p "Read STATE.md in this directory and do exactly what it says. Nothing else." \
  --allowedTools "Read,Write,Edit,Bash" --permission-mode acceptEdits
```

**Verify** the fresh session actually did it, not just claimed to:

```
cat main.tf
checkov -d .
```

`[ Expected output shape ]`
```
variable "log_shipper_key" {
  description = "... Set via TF_VAR_log_shipper_key, never a default."
  type        = string
  sensitive   = true
}
```
```
Exit code: 0
```

Nobody re-explained the task to that session. Nobody re-argued the decision.
It read one file and finished the job correctly, because the file, not the
conversation, was carrying the plan. That's Route. A conversation you clear is
gone. A file on disk is still there.

## Which failure was which

Not every mistake an agent makes is a context problem. **Note** the
difference, because it's the seam between this module and M06:

- The secret-in-`default` mistake was context: nobody told the agent the
  rule, so it reached for the fastest thing that worked. Writing the rule
  down fixed it completely, on the first try.
- A mistake like "the agent wrote correct code but ran `terraform apply`
  before showing you the plan" is not a context problem. The agent might
  know the rule perfectly and still skip the step under time pressure. That
  needs a harness gate that makes the skip impossible, not a file that asks
  nicely. M06 builds that gate.

#### Exercise

Delete one section from your own `AGENTS.md`, the naming convention or the
provider pins, and run the exact same intent a third time. Does the mistake
that section was preventing come back? Then, separately, write a `STATE.md`
of your own for something you're actually mid-way through this week, not a
lab exercise, a real piece of work. Write three lines in `notes.md`: which
`AGENTS.md` line turned out to be load-bearing, what surprised you about
handing your real `STATE.md` to a fresh session, and which of the three
disciplines, reduce, retain, route, you were worst at before this lab.

#### Summary

One small module, built three times, three pieces of evidence. Reduce: one
flag cut a real scan's output by 85% without losing a single finding. Retain:
the same intent, on the same module, twice, differed only by one file the
agent read before it started. Route: a fresh session with zero memory picked
up that same module mid-fix and finished it correctly, because the plan lived
on disk, not in the conversation that had already been cleared. None of this
was a cleverer prompt or a bigger model. It was managing a resource that
resets, on purpose, in three specific ways, on one real piece of infrastructure
you can point to. M06 picks up where Retain's second finding leaves off: the
gate for mistakes that writing something down can't fully prevent.

##### Reading List

- [Anthropic: Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- `reading/concepts.md` in this module: the full Reduce/Retain/Route
  breakdown, and the information-gap finding, 11 of 14 policy failures
  resolved by making policy text visible
- M01's `reading/concepts.md`: the three-layer diagnostic this lab's last
  section applies
- M12's `reading/concepts.md`: the real, measured number behind automated
  context-compression tools, checked against their marketing claims

##### Search Keywords

- context engineering: reduce, retain, route
- AGENTS.md, CLAUDE.md, standing context
- checkov --compact, filtering tool output
- STATE.md, fresh session, context reset
- context window, context engineering vs prompt engineering
- retrieval, repo shape
- sensitive variable, TF_VAR_
- three-layer diagnostic: context, harness, loop

##### Re-verify

`lab/run.sh` checks both runs for real: run 1 must fail checkov on
`CKV_SECRET_2`, run 2 must be clean, and `AGENTS.md` must carry all four
required sections. Run it whenever the pinned provider or checkov versions in
this lab get bumped:

```
cd modules/module-03-context-engineering/lab
./run.sh
```
