# Lab 2: Your Agentic IaC Workstation

**Tier 0** · ~15 min · no cloud account, no `terraform apply` required. Claude Code (or Codex),
Terraform, and Checkov, all already in the devcontainer.

Lab 1 had you run a generate-verify-fix loop by hand, no agent involved. This lab hands the
first half of that loop, just the generating, to a real agent, twice, on the same intent, so
you feel the difference between step 1 and step 2 on the autonomy ladder instead of only
reading about it.

## Pre Requisites

- Claude Code or Codex CLI, installed and authenticated. Verify with a version check:

```
claude --version
```

or

```
codex --version
```

- Everything from Lab 1's pre-requisites still applies: `terraform`, `checkov`, and Docker
  reachable at `/var/run/docker.sock`.

```
terraform version
checkov --version
docker info
```

If any of these fail, fix them before continuing. This module doesn't introduce anything
beyond what Lab 1 already needed, plus the agent CLI itself.

## Two real dials: which tools, and how much permission

Before you run anything, know what you're actually turning on and off. Claude Code gives you
two separate controls: which tools the agent may call at all, and how much it can do with them
without stopping to ask you.

**Day to day, you won't set these with flags.** You'll type `claude` and land in an
interactive session. The first time the agent wants to touch a file or run a command, it stops
and asks: allow this once, allow it for the rest of this session, or deny it. Press
**Shift+Tab** to cycle the session's permission mode right there in the prompt, normal ask-first,
through auto-accepting edits, to plan mode. Type **`/permissions`** to open the actual
allow/deny list and edit it directly, add `Bash(terraform *)` to let the agent run terraform
commands without asking every single time, without handing it an open shell. If you want a
session where nothing stops to ask at all, that's `claude --dangerously-skip-permissions`, and
you reach for it with your eyes open, not by accident, the CLI's own help text says it plainly:
recommended only for sandboxes with no internet access.

That's the real day-to-day workflow, and it's worth trying right now before this lab moves on
to anything scripted: run `claude`, ask it something small about this repo, watch the
permission prompt actually appear, then press Shift+Tab and watch the mode indicator change.

**This lab's actual steps use `-p` and CLI flags instead, on purpose, not because that's how
you'll normally work.** A lab has to be copy-pasteable and give the same result every time you
run it, an interactive back-and-forth can't be scripted that way. `--allowedTools` is the
non-interactive equivalent of the allow/deny list `/permissions` edits for you; leave it empty
and the agent can only talk, it can't touch your filesystem or run a command at all.
`--permission-mode` is the non-interactive equivalent of the Shift+Tab cycle, six real values,
run `claude --help` yourself to confirm this list hasn't drifted:

| Mode | Interactive equivalent |
|---|---|
| `manual` / `auto` | The normal ask-before-each-tool-call default |
| `acceptEdits` | Shift+Tab once, into auto-accept-edits |
| `plan` | Shift+Tab again, into plan mode |
| `dontAsk` | Fewer prompts, still respects `--allowedTools`/`/permissions` |
| `bypassPermissions` | `claude --dangerously-skip-permissions`, no boundary at all |

Step 1 below uses `--allowedTools ""`, the scripted version of never granting anything, that's
the "suggest" behavior. Step 2 uses `--allowedTools "Write,Edit"`, the scripted version of
allowing edits, that's "draft." `plan` mode is previewed later in this lab, it's the real
mechanism behind step 3 on the ladder, properly taught starting M04. `bypassPermissions` isn't
used anywhere in this course before you understand exactly what it removes.

## The intent, again

Same one-line prompt from Lab 1, on purpose. You already know what a good answer to it looks
like, that's what makes the comparison in this lab meaningful:

> Give me a local nginx container for testing, serving a static page I control, with its
> rendered HTML kept on disk so I can diff it in git. No secrets in the container. I don't
> need it exposed outside this machine.

## Step 1: suggest, you type it

**Ask** your agent for a suggestion only, don't let it touch any file yet. In Claude Code,
that means running it without file-write tools available:

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
mkdir -p ~/m02-lab/step1-suggested
cd ~/m02-lab/step1-suggested
```

`file: ~/m02-lab/step1-suggested/main.tf`

Copy the block above into this file, however you'd normally do that, paste it, redirect the
agent's raw output into it with `> main.tf`, whatever's fastest for you. Then run the syntax
floor from Lab 1 on it:

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

`edit file: ~/m02-lab/step1-suggested/main.tf`
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

## Step 2: draft, the agent writes it

**Ask** the same agent the same intent again, in a fresh session, this time letting it write
the file directly:

```
mkdir -p ~/m02-lab/step2-drafted
cd ~/m02-lab/step2-drafted
claude -p "Write a Terraform module (main.tf) in the current directory implementing this
intent directly. Do not ask questions, just write the file. Intent: <paste the intent above>"
--allowedTools "Write,Edit"
```

**Read** `main.tf` before you do anything else with it, the same discipline Lab 1's `terraform
plan` step asked for. Then run the same syntax floor:

```
terraform fmt -check -diff
terraform init -backend=false -input=false
terraform validate
```

`[ Expected output ]`
```
Success! The configuration is valid.
```

No fix needed this time, this real run's draft validated clean on the first try. That's not a
guarantee, it's what happened once. Read every line anyway, every time, that's the whole
lesson of step 2.

## Preview: what plan mode actually does

Step 2 let the agent write a file straight away. There's a real middle setting between "just
talk" and "just write": `--permission-mode plan`. **Try** it on a fresh throwaway ask:

```
mkdir -p ~/m02-lab/plan-preview && cd ~/m02-lab/plan-preview
claude -p "A single local_file resource writing 'hello' to hello.txt. Propose the change." \
  --permission-mode plan
```

`ls` the directory afterward. No `hello.txt`, no `main.tf`, nothing got written. Instead, the
agent produced a real plan document, saved under `~/.claude/plans/`, roughly shaped like this
(your exact wording will differ, plan mode isn't deterministic, the shape is what matters):

`[ Expected output shape ]`
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
against. For now, just notice the shape: step 1 gave you text with no structure, step 2 gave
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
@@ -4,43 +4,69 @@
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
+}
+
+variable "host_port" {
+  description = "Port on localhost to bind nginx to (loopback only, not exposed externally)"
+  type        = number
+  default     = 8080
+}
+
+resource "local_file" "index_html" {
+  filename = "${path.module}/html/index.html"
+  content  = <<-EOT
+    ...
+  EOT
 }

 resource "docker_image" "nginx" {
-  name         = "nginx:1.27-alpine"
+  name         = "nginx:alpine"
   keep_locally = true
 }

 resource "docker_container" "nginx" {
-  name  = "local-nginx-test"
+  name  = var.container_name
   image = docker_image.nginx.image_id

   volumes {
-    host_path      = var.site_dir
-    container_path = "/usr/share/nginx/html"
+    host_path      = local_file.index_html.filename
+    container_path = "/usr/share/nginx/html/index.html"
     read_only      = true
   }
```

Same intent, same model, two different, both individually reasonable, designs. Step 1's file
bind-mounts a directory you edit by hand. Step 2's file has Terraform itself write the HTML
through a `local_file` resource. Neither is wrong against the intent. Would you have expected
the agent to remember what it told you in step 1 when you started step 2? It doesn't, unless
something gives it that memory on purpose, and this run had nothing. Every fresh session
starts cold, with only the intent you gave it.

## Check both with checkov

```
cd ~/m02-lab/step1-suggested && checkov -d .
cd ~/m02-lab/step2-drafted && checkov -d .
```

`[ Expected output ]`
```
Exit code: 0
```

Same gap from Lab 1: no secrets, and neither `docker_container` nor `local_file` has built-in
Checkov coverage, so a clean exit here means "found nothing to flag," not "audited and safe."

#### Exercise

Write a short note, in your own words, in a file called `notes.md` next to your two modules:

- What felt different between typing step 1's suggestion and reading step 2's draft?
- If you had to pick only one to keep doing for the rest of this course, which one, and why?
- You just saw three real permission postures: no tools at all, `Write`/`Edit` allowed with
  the interactive default, and `plan` mode. If this were a real production repo, not a lab,
  which one would you want an agent running against by default, and what would have to be true
  before you'd loosen it? `bypassPermissions` exists too, you didn't use it here, say why not.

Keep the file, same as Lab 1's note, you'll compare both against your capstone answer.

#### Summary

You stood up a real agentic IaC workstation and ran the same intent through it twice, once as
a suggestion you typed, once as a file it wrote. Both are on the autonomy ladder from module
1, steps 1 and 2, the two lowest steps, the ones where you keep the most direct control.
Module 3 is where you start giving the agent standing context, `CLAUDE.md` and `AGENTS.md`,
instead of retyping the same intent details every session.

##### Reading List

- [Claude Code CLI reference](https://docs.claude.com/en/docs/claude-code/cli-reference)
- [Codex CLI documentation](https://developers.openai.com/codex/cli)
- `reading/concepts.md` in this module: why two CLIs, what the devcontainer pins and why, and
  the full "what actually differed" finding

##### Search Keywords

- Claude Code, Codex CLI, devcontainer
- step 1 suggest, step 2 draft, step 3 plan mode, autonomy ladder
- `--allowedTools`, `--permission-mode`, `bypassPermissions`
- terraform fmt, terraform validate
- `path.module`, variable defaults
