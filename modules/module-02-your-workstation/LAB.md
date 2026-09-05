# Project 02: Build an Nginx Test Module Using Claude Code's Agent Modes

**Tier 0** · ~15 min · no cloud account, no `terraform apply` required. Claude Code (or Codex),
Terraform, and Checkov, all installed on your host per Environment Setup.

In this project, you will build one real thing: a local nginx test module, a container that
serves a static page you control, its rendered HTML kept on disk so you can diff it in git,
later extended with a second page and a health-check endpoint. You will build the same module
five times over, same intent every time. What changes each time is how much of the work you
hand to the agent, and how much permission it runs with.

**What you're building, at a glance:**

- A working nginx module, typed as a suggestion, then written as a draft by the agent
- A real bug caught twice, independently, by two different agent sessions
- A preview of plan mode on a throwaway file, before the real thing lands in M04
- The module extended under `acceptEdits` while you watch, applied and destroyed for real
- A bounded audit delegated to a subagent, its narrower permissions doing their job
- This module's own set of required checks turned into a one-word slash command

M01 had you run a generate-verify-fix loop by hand, no agent involved. This project hands the
first half of that loop, just the generating, to a real agent, on the same intent, so you feel
the difference between step 1 and step 2 on the autonomy ladder instead of only reading about
it.

## Pre Requisites

- Claude Code or Codex CLI, installed and authenticated. Verify with a version check:

```
claude --version
```

or

```
codex --version
```

- Everything from M01's pre-requisites still applies: `terraform`, `checkov`, and Docker
  reachable at `/var/run/docker.sock`.

```
terraform version
checkov --version
docker info
```

If any of these fail, fix them before continuing. This project doesn't introduce anything
beyond what M01 already needed, plus the agent CLI itself.

## Two real dials: which tools, and how much permission

Before you run anything, know what you're actually turning on and off. Claude Code gives you
two separate controls: which tools the agent may call at all, and how much it can do with them
without stopping to ask you. **This is how you'll actually use them, day to day:**

Type `claude` and land in an interactive session. The first time the agent wants to touch a
file or run a command, it stops and asks: allow this once, allow it for the rest of this
session, or deny it. That prompt, appearing and you answering it, **is** the tool/permission
system in normal use, not a flag you set in advance. Press **Shift+Tab** to cycle the session's
permission mode right there in the prompt, normal ask-first, through auto-accepting edits, to
plan mode. Type **`/permissions`** to open the actual allow/deny list and edit it directly, add
`Bash(terraform *)` to let the agent run terraform commands without asking every single time,
without handing it an open shell. If you want a session where nothing stops to ask at all,
that's `claude --dangerously-skip-permissions`, launched that way from the start, and you reach
for it with your eyes open, not by accident, the CLI's own help text says it plainly:
recommended only for sandboxes with no internet access.

| Mode | How you actually reach it |
|---|---|
| `manual` / `auto` | Nothing to do, it's the default. The prompt just appears |
| `acceptEdits` | Shift+Tab once, mid-session |
| `plan` | Shift+Tab again, mid-session |
| `dontAsk` | Fewer prompts, still respects your `/permissions` list |
| `bypassPermissions` | Launch as `claude --dangerously-skip-permissions` |

`--allowedTools` and `--permission-mode` are the same six behaviors as CLI flags instead of a
keypress, real, documented (`claude --help` yourself to confirm this list hasn't drifted), and
this lab's copy-pasteable steps use them for one honest reason: a lab guide has to show you
exact, real, reproducible output, and an interactive back-and-forth can't be pasted into a
static page the same way twice. **Do each step interactively first, the way you actually would.
The flagged command underneath it is the scripted capture of that same action, not a
replacement for it.**

## The intent, again

Same one-line prompt from M01, on purpose. You already know what a good answer to it looks
like, that's what makes the comparison in this project meaningful:

> Give me a local nginx container for testing, serving a static page I control, with its
> rendered HTML kept on disk so I can diff it in git. No secrets in the container. I don't
> need it exposed outside this machine.

## Step 1: Suggest Mode

**Open** `claude` and ask it the intent above, plainly, the way you would in any real session.
If it reaches for a tool to write a file, **deny** it right there at the permission prompt,
that's you controlling step 1 in real time, not a flag set in advance. Either way you'll get a
suggestion back as chat text.

```
claude
```
```
> Give me a local nginx container for testing, serving a static page I control, with its
  rendered HTML kept on disk so I can diff it in git. No secrets in the container. I don't
  need it exposed outside this machine. Just show me the Terraform, don't write any files yet.
```

**For this lab guide to show you exact, reproducible output**, here's the same ask, scripted,
with the tool boundary set up front instead of denied live (`--allowedTools ""` means there's
nothing to even prompt you for):

```
claude -p "You are helping with a Terraform module. Do NOT write or create any files. Just
SUGGEST the Terraform HCL as text in your response, as a single code block, nothing else.
Intent: <paste the intent above>" --allowedTools ""
```

`[ Expected output ]`
```
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

variable "site_dir" {
  description = "Path to local dir with static HTML you author/edit"
  type        = string
  default     = "${path.module}/site"
}

resource "docker_image" "nginx" {
  name         = "nginx:1.27-alpine"
  keep_locally = true
}

resource "docker_container" "nginx" {
  name  = "local-nginx-test"
  image = docker_image.nginx.image_id

  volumes {
    host_path      = var.site_dir
    container_path = "/usr/share/nginx/html"
    read_only      = true
  }

  ports {
    internal = 80
    external = 8080
    ip       = "127.0.0.1"
  }

  restart = "no"
}

output "url" {
  value = "http://127.0.0.1:8080"
}
```

That's a real, captured response, not a mock. This is exactly what step 1 looks like in
practice: the agent never touched a file, you're the one moving its answer into your repo, the
same way you'd copy a suggestion out of a chat window or a code review comment:

```
mkdir -p modules/module-02-your-workstation/lab/step1-suggested
cd modules/module-02-your-workstation/lab/step1-suggested
```

`file: main.tf`

Copy the block above into this file, however you'd normally do that, paste it, redirect the
agent's raw output into it with `> main.tf`, whatever's fastest for you. Then run the same basic checks from M01 on it:

```
terraform fmt -check -diff
terraform init -backend=false -input=false
terraform validate
```

`[ Expected output ]`
```
Error: Variables not allowed

  on main.tf line 15, in variable "site_dir":
  15:   default     = "${path.module}/site"

Variables may not be used here.
```

The suggestion doesn't validate. `path.module` isn't available inside a `variable` block's
`default`, only inside resources and outputs. This is exactly step 1's whole point: typing a
suggestion doesn't make it correct, it makes it **yours to have caught**. **Fix** it to a plain
relative path:

`edit file: main.tf`
```
variable "site_dir" {
  description = "Path to local dir with static HTML you author/edit"
  type        = string
  default     = "./site"
}
```

Create the site directory the variable points at, then re-validate:

```
mkdir -p site
echo '<html><body><h1>Module 02 lab, step 1</h1></body></html>' > site/index.html
terraform validate
```

`[ Expected output ]`
```
Success! The configuration is valid.
```

**`terraform validate` alone is not enough.** It checks types and syntax, not every constraint a
provider enforces once it actually has to act on your values. Run `terraform plan` on this same
file:

```
terraform plan
```

`[ Expected output ]`
```
Error: './site' must be an absolute path

  with docker_container.nginx,
  on main.tf line 23, in resource "docker_container" "nginx":
  23: resource "docker_container" "nginx" {

'./site' must be an absolute path
```

That's a real, captured error, not a hypothetical. The `docker_container` resource's
`volumes.host_path` has to be an absolute path, a rule the docker provider enforces once it plans
the actual create, and `terraform validate` never evaluates. Your file validated clean and would
still have failed the moment anyone tried to plan or apply it. **Fix** it by wrapping the
reference in `abspath()` at the point Docker actually needs it:

`edit file: main.tf`
```
  volumes {
    host_path      = abspath(var.site_dir)
    container_path = "/usr/share/nginx/html"
    read_only      = true
  }
```

Re-plan:

```
terraform plan
```

`[ Expected output ]`
```
Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + url = "http://127.0.0.1:8080"
```

Clean. Two real bugs in one suggestion, both caught before anything ran: a `variable` default
that referenced `path.module` where Terraform doesn't allow it, and a relative path a provider
rejects at plan time. `terraform validate` caught the first, on its own it can't see the second,
only `terraform plan` did. Both were yours to have caught either way.

## Step 2: Draft Mode

Same project, same intent, more trust. **Open** a fresh `claude` session in a new directory, same intent, and this time when the
permission prompt appears asking to write `main.tf`, **approve** it. That's the whole
mechanism, you didn't need a flag, you just said yes at the prompt instead of no:

```
mkdir -p modules/module-02-your-workstation/lab/step2-drafted && cd modules/module-02-your-workstation/lab/step2-drafted
claude
```
```
> Write a Terraform module (main.tf) in this directory implementing this intent directly:
  Give me a local nginx container for testing, serving a static page I control, with its
  rendered HTML kept on disk so I can diff it in git. No secrets in the container. I don't
  need it exposed outside this machine.
```

**Scripted, for a reproducible capture** (same ask, tools granted up front instead of approved
live at the prompt):

```
claude -p "Write a Terraform module (main.tf) in the current directory implementing this
intent directly. Do not ask questions, just write the file. Intent: <paste the intent above>"
--allowedTools "Write,Edit"
```

**Read** `main.tf` before you do anything else with it, the same discipline M01's `terraform
plan` step asked for. Then run the same basic checks:

```
terraform fmt -check -diff
terraform init -backend=false -input=false
terraform validate
```

`[ Expected output ]`
```
Success! The configuration is valid.
```

Validated clean on the first try. Before you call that "no fix needed," remember step 1's
lesson: validate is not enough, plan catches more. Run it:

```
terraform plan
```

`[ Expected output ]`
```
Error: './html/index.html' must be an absolute path

  with docker_container.nginx,
  on main.tf line 51, in resource "docker_container" "nginx":
  51: resource "docker_container" "nginx" {

'./html/index.html' must be an absolute path
```

Same bug, independently. The agent's draft wrote `filename = "${path.module}/html/index.html"`
on `local_file.index_html`, and that resource's `filename` feeds straight into the container's
`host_path`. Two different sessions, two different designs, the exact same real plan-time
failure, because neither the model nor `terraform validate` catches Docker's absolute-path
requirement. **Fix** it the same way, wrapping the reference in `abspath()`:

`edit file: main.tf`
```
resource "local_file" "index_html" {
  filename = abspath("${path.module}/html/index.html")
```

Re-plan:

```
terraform plan
```

`[ Expected output ]`
```
Plan: 3 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + url = "http://127.0.0.1:8080"
```

Clean. "Draft validated on the first try" was true and still wasn't the whole story, that's the
actual lesson of step 2, sharper than the version of it you'd have gotten by stopping at
`validate`. Read every line anyway, every time, and run `plan`, every time, that's the whole
lesson.

## Step 3: Plan Mode

A third posture, on a throwaway file, not the project itself. Step 2 let the agent write a
file straight away. There's a real middle setting between "just talk" and "just write."
**Open** `claude` in a fresh directory and press **Shift+Tab** until
the mode indicator at the bottom of the prompt reads `plan mode`, then ask it a small throwaway
thing:

```
mkdir -p modules/module-02-your-workstation/lab/plan-preview && cd modules/module-02-your-workstation/lab/plan-preview
claude
```
```
[Shift+Tab, Shift+Tab, until the prompt shows: plan mode on]
> A single local_file resource writing 'hello' to hello.txt. Propose the change.
```

**Scripted equivalent**, same throwaway ask, mode set as a flag instead of Shift+Tab:

```
claude -p "A single local_file resource writing 'hello' to hello.txt. Propose the change." \
  --permission-mode plan
```

`ls` the directory afterward. No `hello.txt`, no `main.tf`, nothing got written. Instead, the
agent produced a real plan document, saved under `~/.claude/plans/`, in roughly this pattern
(your exact wording will differ, plan mode isn't deterministic, the pattern is what matters):

`[ Approximate output ]`
```
# Plan: hello.txt via local_file

## Context
<what it found in the directory, what's already there>

## Approach
<the HCL it intends to write, as a preview, not yet applied>

## Verification
<init / validate / apply / read-back, stated up front>
```

That's the real mechanism behind step 3 on the ladder, propose with plan: the agent hands you
a plan, not a fait accompli, and waits for you to say go. This course teaches step 3 properly
starting M04, once there's a real skill and a real repo convention for the agent to plan
against. For now, just notice the pattern: step 1 gave you text with no structure, step 2 gave
you a finished file, step 3 gives you a reviewable plan, ordered by how much it commits before
you've said yes to anything.

## What actually differed

**Diff** the two files:

```
diff -u step1-suggested/main.tf step2-drafted/main.tf
```

`[ Expected output ]`
```
--- step1-suggested/main.tf
+++ step2-drafted/main.tf
@@ -4,45 +4,72 @@
       source  = "kreuzwerker/docker"
       version = "~> 3.0"
     }
+    local = {
+      source  = "hashicorp/local"
+      version = "~> 2.5"
+    }
   }
 }
 
 provider "docker" {}
 
-variable "site_dir" {
-  description = "Path to local dir with static HTML you author/edit"
+variable "container_name" {
+  description = "Name of the local nginx test container"
   type        = string
-  default     = "./site"
+  default     = "nginx-local-test"
 }
 
+variable "host_port" {
+  description = "Port on localhost to bind nginx to (loopback only, not exposed externally)"
+  type        = number
+  default     = 8080
+}
+
+# Static page content lives here on disk, tracked in git, so changes are diffable.
+# abspath() matters here: docker_container.volumes.host_path below must be
+# absolute, a constraint the docker provider enforces at plan time, not
+# something terraform validate checks
+resource "local_file" "index_html" {
+  filename = abspath("${path.module}/html/index.html")
+  content  = <<-EOT
+    ...
+  EOT
+}
+
 resource "docker_image" "nginx" {
-  name         = "nginx:1.27-alpine"
+  name         = "nginx:alpine"
   keep_locally = true
 }
 
 resource "docker_container" "nginx" {
-  name  = "local-nginx-test"
+  name  = var.container_name
   image = docker_image.nginx.image_id
 
-  volumes {
-    host_path      = var.site_dir
-    container_path = "/usr/share/nginx/html"
-    read_only      = true
-  }
-
   ports {
     internal = 80
-    external = 8080
-    ip       = "127.0.0.1" # localhost only, no external exposure
+    external = var.host_port
+    ip       = "127.0.0.1" # loopback only, not reachable from outside this machine
   }
 
-  # no env vars / secrets passed
-  restart = "no"
+  volumes {
+    host_path      = local_file.index_html.filename
+    container_path = "/usr/share/nginx/html/index.html"
+    read_only      = true
+  }
+
+  # No env vars, no secrets passed to the container.
 }
 
 output "url" {
-  value = "http://127.0.0.1:8080"
+  value = "http://127.0.0.1:${var.host_port}"
 }
```

Same intent, same model, two different, both individually reasonable, designs. Step 1's file
bind-mounts a directory you edit by hand. Step 2's file has Terraform itself write the HTML
through a `local_file` resource. Neither is wrong against the intent. Would you have expected
the agent to remember what it told you in step 1 when you started step 2? It doesn't, unless
something gives it that memory on purpose, and this run had nothing. Every fresh session
starts cold, with only the intent you gave it. Notice, though, what both runs got wrong the
same way: neither suggestion used `abspath()` unprompted. Two independent sessions, same
blind spot, because nothing in either run's context ever told the agent Docker needs it, that's
a preview of module 3's whole argument, a fact worth writing down once instead of caught by
hand twice.

## Check both with checkov

```
cd modules/module-02-your-workstation/lab/step1-suggested && checkov -d .
cd ../step2-drafted && checkov -d .
```

`[ Expected output ]`
```
Exit code: 0
```

Same gap from M01: no secrets, and neither `docker_container` nor `local_file` has built-in
Checkov coverage, so a clean exit here means "found nothing to flag," not "audited and safe."

## Step 4: acceptEdits Mode

Back to the real project, now grown, not rebuilt: this step takes step 2's fixed module and
extends it. Step 2 approved one file write, once. `acceptEdits` mode keeps every future edit
in this session
approved automatically, no more per-file prompts, while you still watch each one happen, turn by
turn, in the transcript. **Open** a fresh session in a copy of your fixed `step2-drafted` module
and press **Shift+Tab** until the mode indicator reads `accept edits`:

```
cp -r modules/module-02-your-workstation/lab/step2-drafted modules/module-02-your-workstation/lab/step3-acceptedits && cd modules/module-02-your-workstation/lab/step3-acceptedits
claude
```
```
[Shift+Tab, until the prompt shows: accept edits on]
> Extend main.tf: add a second static page at /about.html, same local_file + volume mechanism
  already used here, real content about this being a Terraform lab. Add an nginx health-check
  location at /healthz returning 200 "ok", without touching disk on every request.
```

**Scripted, for a reproducible capture** (same ask, mode set as a flag instead of Shift+Tab):

```
claude -p "This directory has an existing Terraform module (main.tf) for a local nginx test
container. Extend it, editing main.tf directly: add a second static page at /about.html (served
alongside the existing index.html, same local_file + volume mechanism already used here) with
real content about this being a Terraform lab, and add an nginx health-check location at
/healthz that returns a 200 with the plain text 'ok', without touching disk on every request. Do
not ask questions, just edit the file." --permission-mode acceptEdits --allowedTools "Read,Write,Edit"
```

`[ Expected output ]`
```
Done. main.tf now:

- `local_file.about_html` → `/usr/share/nginx/html/about.html`, real content about it being a
  Terraform lab.
- `local_file.healthz_conf` → nginx conf snippet, mounted `/etc/nginx/conf.d/healthz.conf`,
  `location = /healthz { return 200 'ok'; }`, answers from memory, no disk read per request
```

That's a real, captured response. First, check what `acceptEdits` didn't skip: **read** the new
`main.tf`. Did the agent keep the `abspath()` convention your fix already established for
`local_file.index_html`, or did it drop back to a raw `path.module` reference on the two new
resources? `acceptEdits` means it stopped asking. It does not mean it stopped needing to be
checked. Confirm it yourself:

```
terraform fmt -check -diff
terraform init -backend=false -input=false
terraform validate
terraform plan
```

`[ Expected output ]`
```
Success! The configuration is valid.
```
```
Plan: 5 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + url = "http://127.0.0.1:8080"
```

Clean, and both new resources did carry `abspath()` forward correctly here, a real run's actual
result, not a guarantee for yours. Confirm it in your own output before you trust it. There's
one more thing static checks can't tell you: nginx only auto-loads `/etc/nginx/conf.d/*.conf`
files at the point they're `include`d inside its own `http` block, and a bare `location` block
dropped in there has to make sense in that context. `terraform plan` has no opinion on nginx's
config grammar, only Terraform's. **Apply this for real** on your machine, where Docker is
reachable, and curl all three paths:

```
terraform apply -auto-approve
curl -i http://127.0.0.1:8080/
curl -i http://127.0.0.1:8080/about.html
curl -i http://127.0.0.1:8080/healthz
terraform destroy -auto-approve
```

Whatever you see, write it in this step's line of your exercise notes below, a real result, not
a predicted one. This is exactly the gap `acceptEdits` leaves open: it removes the per-edit
prompt, it does not remove the need to actually run the thing.

## Step 5: Subagent Delegation

Auditing the project you just built, not adding to it. Not everything you'd check is worth
doing inline. A subagent runs in its own isolated context,
good for a bounded, well-defined check you want an answer to without spending your main
session's context on it, and without giving it more reach than the one task needs. **Open**
`claude` in `step3-acceptedits/` and ask it to delegate:

```
claude
```
```
> Use a subagent (the Task tool) to audit main.tf in this directory: run checkov against this
  directory and report any findings, and separately check whether every local_file resource's
  filename wraps path.module in abspath() the way the existing resources already do. The
  subagent should not edit any files, read-only audit only. Report back what the subagent
  found, in 5 lines or fewer.
```

**Scripted, for a reproducible capture:**

```
claude -p "Use a subagent (the Task tool) to audit main.tf in this directory: run checkov
against this directory and report any findings, and separately check whether every local_file
resource's filename wraps path.module in abspath() the way the existing resources already do.
The subagent should not edit any files, read-only audit only. Report back what the subagent
found, in 5 lines or fewer." --permission-mode acceptEdits --allowedTools "Read,Bash(checkov*),Task"
```

`[ Expected output ]`
```
Audit done, read-only.

- checkov: blocked, Bash perms denied agent. Run yourself: checkov -d .
- abspath check: all 3 local_file resources consistent, filename = abspath("${path.module}/...")
  at lines 33, 50, 74. No violators.
- Matters here: docker provider needs absolute host paths, so pattern is load-bearing not style.
```

That's a real, captured, unedited transcript, checkov call and all. The subagent's checkov
attempt got blocked, its own tool permissions didn't extend as far as the pattern granted to
the parent session, and instead of guessing at an answer it said so and told you to run it
yourself. A subagent inherits an isolated, narrower surface, not a blank check on your
permissions. That is by design, and module 6 turns it into a formal gate.

## Step 6: Custom Slash Command

One last thing the project's own repo can carry: its own required checks, as a command anyone
opening it can run. You've now typed `fmt`, `init`, `validate`, `plan` by hand four times in
this lab. A custom slash
command turns a sequence you run often into one word. **Create** this file:

`file: .claude/commands/tf-check.md`
```
---
description: Run this course's Terraform checks (fmt, validate, plan) against the current directory
---

Run, in order, in the current directory, and report the real output of each:

1. `terraform fmt -check -diff`
2. `terraform init -backend=false -input=false -no-color`
3. `terraform validate -no-color`
4. `terraform plan -no-color`

Stop and report immediately if any step fails. Do not continue past a failure, and do not
summarize a step you didn't actually run.
```

**Open** `claude` in that same directory and invoke it:

```
claude
```
```
> /tf-check
```

`[ Expected output ]`
```
All 4 steps pass.

- fmt -check -diff: clean, no diff
- init: success, providers installed
- validate: "Success! The configuration is valid."
- plan: 5 to add, 0 change, 0 destroy, clean plan
```

A real, captured run. `.claude/commands/` is project-scoped, checked into the repo alongside the
module it belongs to, so anyone (or any agent) working in this directory gets the same
one-word check you just built. That's the last real dial this module teaches: slash commands
turn a repeatable check into a fact the repo carries, not a sequence you re-type or re-explain
every session.

#### Exercise

Write a short note, in your own words, in a file called `notes.md` next to your modules:

- What felt different between typing step 1's suggestion and reading step 2's draft?
- Both step 1 and step 2 validated clean and still failed `terraform plan`. What does that tell
  you about which checks you should actually require, on a real repo, not a lab?
- What did you find when you actually applied `step3-acceptedits` and curled `/healthz`? Write
  the real result, whatever it was.
- The subagent's checkov call got blocked by its own permissions. Why is that the right default,
  not a bug, for a subagent doing a bounded, read-only audit?
- You just saw four real permission postures: no tools at all, `Write`/`Edit` with the
  interactive default, `acceptEdits`, and `plan` mode. If this were a real production repo, not
  a lab, which one would you want an agent running against by default, and what would have to
  be true before you'd loosen it? `bypassPermissions` exists too, you didn't use it here, say
  why not.

Keep the file, same as M01's note, you'll compare it against your capstone answer.

## Validation

Run the full check yourself, all three module versions, against real Terraform and Checkov:

```
cd modules/module-02-your-workstation/lab
./run.sh
```

`run.sh` checks:

- All three versions (`step1-suggested`, `step2-drafted`, `step3-acceptedits`) `fmt`,
  `init`, and `validate` clean
- All three `plan` clean, the check `validate` alone missed
- Every `local_file`/`host_path` reference wraps `path.module` in `abspath()`, the real bug
  this project found
- All three are checkov-clean
- Step 1 and step 2's files genuinely differ, the core finding this project depends on
- The `tf-check` slash command exists and is well-formed

## Summary

What you built:

- One project, the local nginx test module, built five times over: typed as a suggestion,
  written as a draft, extended under `acceptEdits` while you watched, audited by a subagent,
  and given its own one-word check
- A real bug, caught twice, independently, by two different agent sessions: `terraform
  validate` never saw it, only `terraform plan` did
- A bounded audit delegated to a subagent, its narrower permissions doing their job instead of
  guessing past them
- A slash command that turns a repeatable check into a fact the repo carries, not something
  re-typed every session

Same intent throughout, only the posture changed. Suggest, draft, and `acceptEdits` are the
autonomy ladder's first two steps, from M01, the ones where you keep the most direct control.
Module 3 is where you start giving the agent standing context, `CLAUDE.md` and `AGENTS.md`, so
a fact like "wrap `path.module` file paths in `abspath()` for Docker" gets written down once
instead of rediscovered by hand.
- slash commands, `.claude/commands/`
- terraform fmt, terraform validate, terraform plan
- `path.module`, `abspath()`, absolute host paths, docker provider
