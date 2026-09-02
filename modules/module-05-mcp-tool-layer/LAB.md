# Project 05: Build an RDS Module Using the Terraform MCP Server

**Tier 1** · ~40 min · Docker required. Real `terraform apply` against Floci, no cloud
account. A later stage opens a real, throwaway pull request on your own repository.

In this project, you will build a real RDS database, tuned with a non-default parameter
group, the kind of resource whose exact arguments you would normally have to look up by
hand. You will connect the official Terraform MCP server, ask the same real question with
and without it, then use it to build and verify the database against Floci. Along the way
you will try a second, AWS-specific MCP server, and a third one to open a real pull request,
watching a human decision hold even when the agent is talking to a live API instead of a
diagram.

**What you're building, at a glance:**

- The same real question, asked twice: once from memory, once through the Terraform MCP
  server, then diffed
- A real RDS instance with a non-default parameter group (`slow_query_log`,
  `long_query_time`), applied, verified, and destroyed against Floci
- A second AWS-specific MCP server, tried live, found broken on startup, a real lesson that
  "official" and "ready" are not the same claim
- A third MCP server, connected to GitHub, used to open a real pull request
- A real PR, opened then closed without merging, the human decision still in place

## Pre Requisites

- Docker running, reachable from your shell (`docker info` should not error)
- The GitHub CLI, authenticated: `gh auth status`
- A repository you're willing to push a throwaway branch to and open a real PR against. Use
  your own fork of the course labs repo, or any repo you own
- Floci running for the RDS build later in this project: `docker compose -f
  ../../../labs/shared/docker-compose.floci.yml up -d`, then confirm with `curl
  http://localhost:4566/_floci/health`

Before connecting a real MCP server you didn't build, audit it the way M04 taught you:
compare its stated purpose against every capability it actually grants your agent,
whether or not the vendor calls it official. A server this course names explicitly and
one you find yourself on a marketplace deserve the same read.

## Stage 1: Connect the Terraform MCP Server

HashiCorp ships the official Terraform MCP server as a Docker image, not an npm package.
**Pull** it first:

```
docker pull hashicorp/terraform-mcp-server:latest
```

`[ Expected output ]`
```
Status: Downloaded newer image for hashicorp/terraform-mcp-server:latest
docker.io/hashicorp/terraform-mcp-server:latest
```

**Register** it with your agent:

```
claude mcp add --transport stdio terraform -- docker run --rm -i hashicorp/terraform-mcp-server:latest stdio
```

`file: lab/mcp-config/terraform.mcp.json` has the same config as a plain JSON file, in
case your setup reads config from a file instead of the CLI. `[...]` see that file for the
exact contents.

**Verify** the connection:

```
claude mcp get terraform
```

`[ Expected output ]`
```
terraform:
  Scope: Local config (private to you in this project)
  Status: ✔ Connected
  Type: stdio
  Command: docker
  Args: run --rm -i hashicorp/terraform-mcp-server:latest stdio
```

## Stage 2: Prove you actually need it

Here's the one-line intent: "What's the latest version of the kreuzwerker/docker Terraform
provider, and what arguments does its `healthcheck` block accept?"

**Ask** it first with no MCP tool available, from memory only:

```
claude -p --strict-mcp-config "Without searching the web or using any tools, from what you already know: what is the exact latest version number of the kreuzwerker/docker Terraform provider, and what is the full list of top-level arguments the docker_container resource's healthcheck block accepts? Answer from memory only, give your best specific answer even if you're not fully sure."
```

`file: lab/evidence/stale-answer.txt` has the real captured answer from building this
project. Your own run will differ in wording, but watch for the same pattern: a guess, low
confidence, maybe a version number that's several minors behind.

**Ask** the identical question again, this time letting the agent actually use the tool:

```
claude -p "Using the terraform MCP tools available to you, look up the exact latest version number of the kreuzwerker/docker Terraform provider on the registry, and the full list of top-level arguments the docker_container resource's healthcheck block accepts. Cite what the tool actually returned."
```

`file: lab/evidence/mcp-answer.txt` has the real captured answer, including which MCP tool
the agent actually called. Diff the two. The gap between them is the whole lesson.

## Stage 3: Build the RDS module with a non-default parameter group

A stale-vs-live lookup proves the point. Building something proves you can use it.
`aws_db_parameter_group` is a good resource to learn this on: most learners have never
written one by hand, so there's no memorized answer to fall back on, you actually need the
live lookup.

**Ask** the agent to look up the resource's arguments, then check the answer against what it
actually returned:

```
claude -p "Using the terraform MCP tools available to you, look up the aws_db_parameter_group resource in the hashicorp/aws provider. Tell me: the exact required arguments, and what the 'family' argument value should be for a MySQL 8.0 RDS instance. Cite what the tool actually returned." --allowedTools "mcp__terraform__*"
```

`file: lab/evidence/param-group-mcp-answer.txt` has the real captured answer from building
this project. Read it closely, it's a good example of an honest tool response. The MCP
server's docs give the required argument (`family`) as a literal fact from the provider
schema, but they don't give a literal `mysql8.0` example, only `mysql5.6`/`mysql5.7`/
`postgres13`. The agent inferred `mysql8.0` from the naming pattern and said so plainly,
rather than presenting a guess as a citation. A good agent keeps that distinction visible:
what the tool told it, versus what it worked out from what the tool told it.

**Apply** the module. `file: lab/module/` has the full build: a minimal VPC (two private
subnets, no internet gateway, this module doesn't need one), a security group scoped to the
VPC's own CIDR, `aws_db_parameter_group.app` with a real non-default setting
(`slow_query_log = 1`, `long_query_time = 2`), and `aws_db_instance.app` wired to it through
`parameter_group_name`.

```
cd lab/module
terraform init
terraform apply -auto-approve
```

`[ Expected output ]`
```
Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

db_endpoint = "172.21.0.2:7001"
parameter_group = "m05-mysql8-slowlog"
```

**Verify** the parameter group is really attached, not just declared alongside the instance:

```
terraform show -json | python3 -c "
import json, sys
d = json.load(sys.stdin)
res = {r['address']: r for r in d['values']['root_module']['resources']}
print('db instance parameter_group_name:', res['aws_db_instance.app']['values']['parameter_group_name'])
print('parameter group name:            ', res['aws_db_parameter_group.app']['values']['name'])
"
```

Both lines should print the same name. If they don't, the parameter group exists but the
instance never picked it up, an easy mistake to miss with this resource pair.

**Destroy** it, this is a project, not a running database:

```
terraform destroy -auto-approve
```

## Stage 4: Try aws-iac-mcp-server

This course's own conventions name `aws-iac-mcp-server` as the modern, AWS-endorsed
replacement for the deprecated `awslabs/terraform-mcp-server`. Try it:

```
uvx awslabs.aws-iac-mcp-server@latest --help
```

`file: lab/evidence/aws-iac-mcp-server-attempt.txt` has the real captured output from
building this project. It installs, 86 packages, a real dependency tree including
`cfn-lint` and `botocore`, then crashes on startup with `ModuleNotFoundError: No module
named 'fastmcp.server.proxy'`. Pinning an older `fastmcp` doesn't fix it, it just trades
one crash for a different one, a `pydantic` incompatibility.

Two things are true at once here. `aws-iac-mcp-server` is the genuine AWS Labs package, and
its documented tool list (`validate_cloudformation_template`,
`check_cloudformation_template_compliance`, `search_cdk_documentation`, six more) would be
exactly what you want if part of your stack is CFN or CDK rather than Terraform. As
installed today, in a clean environment, it doesn't start, and even once running, it speaks
CloudFormation and CDK, never Terraform HCL. Verify a server actually connects and actually
covers your tool before you plan a workflow around it, the same caution this course already
gives Floci itself as a still-maturing project.

## Stage 5: Connect the GitHub MCP Server

**Register** the official, hosted GitHub MCP server, using a `gh` token you already have:

```
claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --header "Authorization: Bearer $(gh auth token)"
```

`file: lab/mcp-config/github.mcp.json` is the same config as a file, `$GITHUB_TOKEN`
substituted from your environment instead of inline.

## Stage 6: Ship it, then hand the merge decision to a human

**Create** a throwaway branch with one small, harmless change:

```
git checkout -b m05-mcp-lab-demo
echo "opened by the M05 project, safe to delete" >> mcp-lab-demo.md
git add mcp-lab-demo.md
git commit -m "M05 project: scratch file for the MCP PR-open stage"
git push -u origin m05-mcp-lab-demo
```

**Ask** the agent to open the PR through the MCP tool, not through `gh` directly:

```
claude -p "Using the github MCP tool available to you, open a real pull request from head branch m05-mcp-lab-demo into base branch main on my repository. Title it clearly as a lab demo. Report the exact PR number and URL the tool returned."
```

`file: lab/evidence/pr-opened.json` is the real API response captured from this exact
sequence while building this project: a real PR, `"state": "open"`, a real number and URL.

Read that response again. Nothing merged. The agent's own MCP call stopped at opening the
PR. **Close** it without merging, the human decision:

```
gh pr close <number>
```

`file: lab/evidence/pr-closed.json` shows the same PR afterward: `"state": "closed"`,
`"merged": false`. That's the authority boundary from module 1, holding through a real MCP
tool call, not just in a diagram.

## Exercise

Pick one more MCP server relevant to your own stack (a cloud provider's, a monitoring
tool's, whatever you'd actually reach for). Register it, ask it one real question, and
write two lines: what real answer came back, and would you have gotten that answer without
it?

## Validation

Run the full check yourself, all three MCP servers and the real RDS build, against a real
Floci container:

```
docker compose -f labs/shared/docker-compose.floci.yml up -d
cd modules/module-05-mcp-tool-layer/lab
./run.sh
```

`run.sh` checks:

- The Terraform MCP Docker image and the MCP config files
- The captured evidence: a low-confidence memory guess, a real MCP tool citation, a real
  `aws_db_parameter_group` lookup, the real `aws-iac-mcp-server` crash, a PR that opened then
  closed without merging
- A real `terraform apply` and `terraform destroy` of the RDS-with-parameter-group module
  against Floci

## Summary

What you built:

- Asked the same real question twice, once from memory, once through the Terraform MCP
  server, and watched a guess turn into a sourced answer
- Applied, verified, and destroyed a real RDS instance with a non-default parameter group
  against Floci
- Tried a second AWS MCP server live and watched it fail to start, official did not mean
  ready
- Connected a third MCP server and watched an agent open a real pull request through it
- Watched a human, not the agent, decide whether that PR merged

MCP adds reach. Module 6 is where you build the gate that MCP servers themselves need to
respect, the same permission-boundary caution already flagged in this chapter's reading.
