# Project 01: Build an Nginx Module Using Terraform and Checkov

**Tier 0** · ~12 min · no agent, no cloud account, no `terraform apply`. Just Terraform and
Checkov, both installed on your host, see Environment Setup.

In this project, you will write a small Terraform module by hand, against a one-line intent,
then run it through the same generate-verify-fix loop an agent runs later in this course:
format, validate, plan, scan, fix. No agent yet, just you and the loop.

**What you're building, at a glance:**

- A real nginx container, serving a static page rendered to disk
- A hardcoded secret, planted on purpose, for Checkov to catch
- A real `terraform plan`, read end to end before anything runs
- A real fix: pull the secret out, mark it `sensitive`, rescan clean
- A first look at what an agent produces for this exact same intent

## Pre Requisites

- Nothing from a later module. `terraform` and `checkov` are installed on your host per
  Environment Setup, and Docker is reachable at `/var/run/docker.sock`. Check that with:

```
docker info
```

If this hangs or errors, stop and fix Docker first. Everything below depends on Terraform
being able to reach the Docker daemon, even though we never `apply`.

## The intent

Here's the one-line prompt. Read it the way an agent would, as the only instruction you get:

> Give me a local nginx container for testing, serving a static page I control, with its
> rendered HTML kept on disk so I can diff it in git. No secrets in the container. I don't
> need it exposed outside this machine.

## Step 1: Get the starter module

A skeleton is already written for you. This isn't a Terraform syntax course yet; it's a
verification-loop course. **Copy** it into your own working directory:

```
cp -r modules/module-01-clickops-to-agents/lab/starter ~/m01-lab
cd ~/m01-lab
```

`file: ~/m01-lab/main.tf`
```
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "docker" {}

# TODO: wire this into a real secrets manager once the course gets to M06 (guardrails).
# For now, hardcoding it is the fastest way to unblock the log-shipping sidecar.
variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships nginx access logs to S3"
  type        = string
  default     = "AKIAABCDEFGHIJKLMNOP"
}

resource "local_file" "index_html" {
  filename = "${path.module}/rendered/index.html"
  content  = "<html><body><h1>Module 01 lab</h1></body></html>"
}

resource "local_file" "log_shipper_env" {
  filename = "${path.module}/rendered/log-shipper.env"
  content  = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
}

resource "docker_image" "nginx" {
  name = "nginx:1.27-alpine"
}

resource "docker_container" "site" {
  name  = "m01-lab-site"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 8080
  }

  volumes {
    host_path      = abspath(local_file.index_html.filename)
    container_path = "/usr/share/nginx/html/index.html"
    read_only      = true
  }
}
```

Read it against the intent above before you run anything. It's a fair reading of the prompt: a
static page, kept on disk, a container that stays local. There's also a `log_shipper_key`
variable that isn't part of the intent at all. Keep that in mind; you'll come back to it.

## Step 2: Check the syntax floor

**Format** the module first. This is the cheapest check there is, and it says nothing about
whether the code is good, only whether it's readable:

```
terraform fmt -diff
```

`[ Expected output ]`
```
```

No output means no diff: the starter is already `fmt`-clean. Now **validate** it:

```
terraform init -backend=false
terraform validate
```

`[ Expected output ]`
```
Success! The configuration is valid.
```

Valid and formatted only means Terraform can parse it. It says nothing about whether it's a good
idea.

## Step 3: Read the plan

**Plan** it, and actually read the output instead of skimming past it:

```
terraform plan
```

`[ Expected output ]`
```
Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # docker_container.site will be created
  + resource "docker_container" "site" {
      + name  = "m01-lab-site"
      ...
      + ports {
          + external = 8080
          + internal = 80
        }
      + volumes {
          + container_path = "/usr/share/nginx/html/index.html"
          + host_path      = ".../rendered/index.html"
          + read_only      = true
        }
    }

  # docker_image.nginx will be created
  + resource "docker_image" "nginx" {
      + name = "nginx:1.27-alpine"
    }

  # local_file.index_html will be created
  + resource "local_file" "index_html" {
      + content  = "<html><body><h1>Module 01 lab</h1></body></html>"
      + filename = "./rendered/index.html"
    }

  # local_file.log_shipper_env will be created
  + resource "local_file" "log_shipper_env" {
      + content  = <<-EOT
            AWS_ACCESS_KEY_ID=AKIAABCDEFGHIJKLMNOP
        EOT
      + filename = "./rendered/log-shipper.env"
    }

Plan: 4 to add, 0 to change, 0 to destroy.
```

Four resources, nothing destructive, nothing surprising. `terraform plan` will tell you a plaintext
key is about to land in a file. If you were reading fast, this is the line you'd miss.

## Step 4: Run Checkov, watch it fail

```
checkov -d .
```

`[ Expected output ]`
```
secrets scan results:

Passed checks: 0, Failed checks: 1, Skipped checks: 0

Check: CKV_SECRET_2: "AWS Access Key"
	FAILED for resource: abac545fc3bf803134bc8f78fb6160a5c6a87b26
	File: /main.tf:31-32

		31 |   default     = "AKIAA**********"
```

`Exit code 1`. Checkov's terraform policy set is mostly written for cloud resources; it has
nothing to say about a `docker_container` or a `local_file` block on its own. What it *does*
check, on every file, in every framework, is whether something that looks like a live credential
is sitting in your source. It found one. That `TODO` comment in the starter file wasn't decoration.
It's exactly the kind of shortcut an agent takes under time pressure, and exactly what a scanner
is for.

## Step 5: Fix it, re-run, get to green

The fix isn't to delete the feature. The log shipper is a real requirement. It's to stop typing
the key into the module. Pull the `default` out of the variable and mark it `sensitive`, so the
value has to come from the environment instead:

`edit file: ~/m01-lab/main.tf`
```
variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships nginx access logs to S3. Set via TF_VAR_log_shipper_key, never a default."
  type        = string
  sensitive   = true
}
```

Re-run the same scan:

```
checkov -d .
```

`[ Expected output ]`
```
Exit code: 0
```

Notice what you *don't* see: no "0 failed" summary line, nothing declared clean. Checkov only
reports on checks it actually ran, and none of its built-in policies target `docker_container` or
`local_file`. The only thing it could ever catch in this module was the literal secret, and now
there isn't one. `echo $?` is your real signal here, not the absence of red text. Remember that:
M09 comes back to exactly this gap, on resources Checkov *does* know how to check, and the
finding count there won't be zero.

If you want to see the container run, you can: `terraform apply`, then `curl localhost:8080`.
Not required for this lab. There's no destroy step either, because there's nothing to tear
down, this lab never applies. That's Tier 0: everything stays on your machine, no cloud bill
to go looking for.

## Preview: the same task, done by an agent

Here's the whole point of doing this by hand first: so you recognize it when a machine does
it. `lab/solution/main.tf` is not just your answer key. It is what a coding agent, working
at **Step 2, draft**, would hand you for this exact intent, the same file, ready for you to
read start to finish before anything runs.

`file: lab/solution/main.tf`
```
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "docker" {}

variable "log_shipper_key" {
  description = "AWS key for the sidecar that ships nginx access logs to S3. Set via TF_VAR_log_shipper_key, never a default."
  type        = string
  sensitive   = true
}

resource "local_file" "index_html" {
  filename = "${path.module}/rendered/index.html"
  content  = "<html><body><h1>Module 01 lab</h1></body></html>"
}

resource "local_file" "log_shipper_env" {
  filename        = "${path.module}/rendered/log-shipper.env"
  content         = "AWS_ACCESS_KEY_ID=${var.log_shipper_key}\n"
  file_permission = "0600"
}

resource "docker_image" "nginx" {
  name = "nginx:1.27-alpine"
}

resource "docker_container" "site" {
  name  = "m01-lab-site"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 8080
  }

  volumes {
    host_path      = abspath(local_file.index_html.filename)
    container_path = "/usr/share/nginx/html/index.html"
    read_only      = true
  }
}
```

The loop an agent runs to get here is the same five steps you just ran by hand: read the
intent, generate a draft, `fmt` and `validate` it, `plan` it, scan it. An agent hits the same
checkov finding you did, for the same reason, reads the same error, and makes the same fix,
pull the secret out, mark it `sensitive`. Nothing about that loop is different. What changes
in M02 is who is typing. You hand an agent this exact intent, it writes you this exact kind
of file, and you read it line by line before you do anything else with it, that's Step 2 on
the ladder, and it's where your agentic IaC workstation starts.

Curious what a full run looks like, further down the road? `demos/m1-agent-preview/` in
this repo has a real, verified example: an agent containerizing a small app, with real
command output, not a mock-up. Nothing there is required for this lab.

#### Exercise

Write three lines, in your own words, in a file called `notes.md` next to your module:

- Which of the steps you just ran (fmt, validate, plan, checkov, the fix) would you hand to a
  machine without watching?
- Which one would you still want to read yourself, every time?
- Why that split?

There's no wrong answer here. Keep the file: you'll compare it against your own answer again at
the end of the course, in the capstone.

## Validation

Run the real check yourself, starter and solution both, whenever the pinned provider or
checkov versions in this project get bumped:

```
cd modules/module-01-clickops-to-agents/lab
./run.sh
```

`run.sh` checks:

- `starter` must fail checkov on `CKV_SECRET_2`
- `solution` must be clean

## Summary

What you built:

- A real nginx container, applied against a plan you read end to end
- A hardcoded secret, caught by Checkov, the same way an agent will hit it later
- A real fix: pull the secret out, mark it `sensitive`, rescan clean
- A first look at what an agent produces for this exact intent, in `lab/solution/main.tf`

Every later module in this course automates one more piece of what you just did by hand: M02
hands the typing to an agent, M06 hands the gate a hook, M09 puts real scanners in front of
`apply`. You'll recognize the pattern each time, because you just did it yourself.
