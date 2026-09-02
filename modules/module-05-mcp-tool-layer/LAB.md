# Lab 5: Look Up the Real Thing, Build the Real Module

**Tier 1** · ~40 min · Docker required. Real `terraform apply` against Floci, no cloud
account. A later part opens a real, throwaway pull request on your own repository.

**The project:** a real RDS database, tuned with a non-default parameter group, the kind of
resource whose exact argument shape you'd normally have to look up by hand. You'll build it
using a live connection to real systems, not a memorized guess. Module 4 gave your agent a
skill it reaches for on its own. This lab gives it something different: MCP, a live tool
connection. You'll ask the same question twice, once without that connection and once with
it, then use the connection to build the database for real, applied and destroyed against
Floci. Along the way you'll also try a second, AWS-specific MCP server, and find out live
that "official" and "works today" are not the same claim, a real lesson, not a hypothetical
one. Last, you'll watch the agent open a real pull request through a third MCP server,
proving the same human-approval boundary from module 1 holds even when the agent is talking
to a live API, not just a diagram.

## Pre Requisites

- Docker running, reachable from your shell (`docker info` should not error)
- The GitHub CLI, authenticated: `gh auth status`
- A repository you're willing to push a throwaway branch to and open a real PR against. Use
  your own fork of the course labs repo, or any repo you own
- Floci running for the RDS build later in this lab: `docker compose -f
  ../../../labs/shared/docker-compose.floci.yml up -d`, then confirm with `curl
  http://localhost:4566/_floci/health`

## Stage 1: connect the tool the project needs first

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
exact shape.

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

## Stage 2: prove you actually need it

Here's the one-line intent: "What's the latest version of the kreuzwerker/docker Terraform
provider, and what arguments does its `healthcheck` block accept?"

**Ask** it first with no MCP tool available, from memory only:

```
claude -p --strict-mcp-config "Without searching the web or using any tools, from what you already know: what is the exact latest version number of the kreuzwerker/docker Terraform provider, and what is the full list of top-level arguments the docker_container resource's healthcheck block accepts? Answer from memory only, give your best specific answer even if you're not fully sure."
```

`file: lab/evidence/stale-answer.txt` has the real captured answer from building this lab.
Your own run will differ in wording, but watch for the same shape: a guess, low confidence,
maybe a version number that's several minors behind.

**Ask** the identical question again, this time letting the agent actually use the tool:

```
claude -p "Using the terraform MCP tools available to you, look up the exact latest version number of the kreuzwerker/docker Terraform provider on the registry, and the full list of top-level arguments the docker_container resource's healthcheck block accepts. Cite what the tool actually returned."
```

`file: lab/evidence/mcp-answer.txt` has the real captured answer, including which MCP tool
the agent actually called. Diff the two. The gap between them is the whole lesson.

## Stage 3: build the project, RDS with a non-default parameter group

A stale-vs-live lookup proves the point. Building something proves you can use it. `aws_db_parameter_group`
is a good resource to learn this on: most learners have never written one by hand, so there's
no memorized shape to fall back on, you actually need the live lookup.

**Ask** the agent to look up the resource shape, then check the answer against what it
actually returned:

```
claude -p "Using the terraform MCP tools available to you, look up the aws_db_parameter_group resource in the hashicorp/aws provider. Tell me: the exact required arguments, and what the 'family' argument value should be for a MySQL 8.0 RDS instance. Cite what the tool actually returned." --allowedTools "mcp__terraform__*"
```

`file: lab/evidence/param-group-mcp-answer.txt` has the real captured answer from building
this lab. Read it closely; it's a good example of an honest tool response. The MCP server's
docs give the required argument (`family`) as a literal fact from the provider schema, but
they don't give a literal `mysql8.0` example, only `mysql5.6`/`mysql5.7`/`postgres13`. The
agent inferred `mysql8.0` from the naming pattern and said so plainly, rather than
presenting a guess as a citation. That's the difference between "the tool told me" and "I
worked this out from what the tool told me," and a good agent keeps that distinction visible.

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
instance never picked it up, a real, easy-to-miss mistake with this resource pair.

**Destroy** it, this is a lab, not a running database:

```
terraform destroy -auto-approve
```

## Stage 4: a second tool for the same project, a real, live disappointment

This course's own conventions name `aws-iac-mcp-server` as the modern, AWS-endorsed
replacement for the deprecated `awslabs/terraform-mcp-server`. Try it:

```
uvx awslabs.aws-iac-mcp-server@latest --help
```

`file: lab/evidence/aws-iac-mcp-server-attempt.txt` has the real captured output from
building this lab. It installs, 86 real packages, a real dependency tree including
`cfn-lint` and `botocore`, then crashes on startup with `ModuleNotFoundError: No module
named 'fastmcp.server.proxy'`. Pinning an older `fastmcp` doesn't fix it, it just trades
one crash for a different one, a real `pydantic` incompatibility.

Two things are true at once here, and both matter. First: `aws-iac-mcp-server` is real,
it's the genuine AWS Labs package, and its documented tool list (`validate_cloudformation_template`,
`check_cloudformation_template_compliance`, `search_cdk_documentation`, six more, all real,
all CloudFormation/CDK-scoped) would be exactly what you want if part of your stack is CFN
or CDK rather than Terraform. Second: as installed today, in a clean environment, it doesn't
start. An MCP server being official doesn't mean it's stable, and an MCP server being
AWS-specific doesn't mean it speaks your IaC tool, this one speaks CloudFormation and CDK,
never Terraform HCL, even once it's running. Verify a server actually connects and actually
covers your tool before you plan a workflow around it, the same caution this course already
gives Floci itself as a still-maturing project.

## Stage 5: connect a third tool, to ship the project safely

**Register** the official, hosted GitHub MCP server, using a `gh` token you already have:

```
claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --header "Authorization: Bearer $(gh auth token)"
```

`file: lab/mcp-config/github.mcp.json` is the same config as a file, `$GITHUB_TOKEN`
substituted from your environment instead of inline.

## Stage 6: ship it, then hand the merge decision to a human

**Create** a throwaway branch with one small, harmless change:

```
git checkout -b m05-mcp-lab-demo
echo "opened by the M05 lab, safe to delete" >> mcp-lab-demo.md
git add mcp-lab-demo.md
git commit -m "M05 lab: scratch file for the MCP PR-open step"
git push -u origin m05-mcp-lab-demo
```

**Ask** the agent to open the PR through the MCP tool, not through `gh` directly:

```
claude -p "Using the github MCP tool available to you, open a real pull request from head branch m05-mcp-lab-demo into base branch main on my repository. Title it clearly as a lab demo. Report the exact PR number and URL the tool returned."
```

`file: lab/evidence/pr-opened.json` is the real API response captured from this exact
sequence while building this lab: a real PR, `"state": "open"`, a real number and URL.

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

## Summary

The project is done: a real RDS database, tuned with a non-default parameter group, applied
and verified and destroyed, built through a live tool connection instead of a memorized
guess. Along the way, you asked the same question twice and watched a guess turn into a
real, sourced answer. You tried a second AWS MCP server and watched it fail to start, a real
reminder that "official" is not "ready." You watched an agent open a real pull request
through a third MCP server, and watched a human, not the agent, decide whether it merged.
MCP adds reach. Module 6 is where you build the gate that MCP servers themselves need to
respect, the same permission-boundary caution already flagged in this chapter's reading.

##### Reading List

- [Model Context Protocol specification](https://modelcontextprotocol.io)
- [HashiCorp Terraform MCP server](https://github.com/hashicorp/terraform-mcp-server)
- [GitHub MCP server](https://github.com/github/github-mcp-server)
- [AWS IaC MCP Server](https://awslabs.github.io/mcp/servers/aws-iac-mcp-server) (CloudFormation/CDK-scoped, not Terraform)

##### Search Keywords

- Model Context Protocol, MCP server, MCP client
- terraform-mcp-server, github-mcp-server, aws-iac-mcp-server
- claude mcp add, mcp tool call
- stale training data, live lookup
- aws_db_parameter_group, aws_db_instance

##### Re-verify

`lab/run.sh` checks the Terraform MCP Docker image, the MCP config files, the captured
evidence (a low-confidence guess, a real MCP tool citation, a real `aws_db_parameter_group`
lookup, the real aws-iac-mcp-server crash, a PR that opened then closed without merging),
**and does a real `terraform apply` and `terraform destroy` of the RDS-with-parameter-group
module against Floci**, start Floci first.

```
docker compose -f labs/shared/docker-compose.floci.yml up -d
cd modules/module-05-mcp-tool-layer/lab
./run.sh
```
