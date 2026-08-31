# Lab 3: Give the Agent What a New Hire Would Get

**Tier 0 → 1** · ~15 min · your own agent (Claude Code or Codex), the same
`terraform` and `checkov` from M01.

M01 had you run a generate-verify-fix loop by hand. This lab asks a narrower
question: does the loop even need the "verify" step as often, if the agent had
better information to start with? You're going to run the exact same intent
twice, once with nothing written down, once with a real `AGENTS.md` in place,
and read the difference for yourself.

## Pre Requisites

- Completed M01's lab, or at least read `reading/concepts.md` for that module.
  This lab reuses M01's exact one-line intent.
- An agent you can prompt directly, Claude Code or Codex, from a terminal in a
  scratch directory.

## The intent, again

Same as M01, read it the way an agent would:

> Give me a local nginx container for testing, serving a static page I control,
> with its rendered HTML kept on disk so I can diff it in git. No secrets in the
> container. I don't need it exposed outside this machine.

## Run 1: no context

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

## Write the context

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

## Run 2: with context

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

## Diff the two runs

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
that section was preventing come back? Write two lines in `notes.md`: which
line turned out to be load-bearing, and how you'd have found that out without
deleting it on purpose.

#### Summary

You ran the same intent twice, and the only thing that changed between the
two runs was one file the agent read before it started. That's context
engineering: not a cleverer prompt, not a bigger model, just the standing
information a new hire would get on day one, written down once and reused on
every run after. M06 picks up where this lab's second finding leaves off: the
gate for mistakes that writing something down can't fully prevent.

##### Reading List

- [Anthropic: Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- `reading/concepts.md` in this module: the information-gap finding, 11 of 14
  policy failures resolved by making policy text visible
- M01's `reading/concepts.md`: the three-layer diagnostic this lab's last
  section applies

##### Search Keywords

- AGENTS.md, CLAUDE.md, standing context
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
