# Lab 5: Look Up the Real Thing, Open a Real PR

**Tier 1** · ~20 min · Docker required. No `terraform apply`, no cloud account for the first
part; the second part opens a real, throwaway pull request on your own repository.

Module 4 gave your agent a skill it reaches for on its own. This lab gives it something
different: a live connection to two real systems. You'll ask the same question twice, once
without that connection and once with it, and see for yourself which answer you'd actually
want to build on.

## Pre Requisites

- Docker running, reachable from your shell (`docker info` should not error)
- The GitHub CLI, authenticated: `gh auth status`
- A repository you're willing to push a throwaway branch to and open a real PR against. Use
  your own fork of the course labs repo, or any repo you own

## Configure the Terraform MCP server

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

## Ask the same question twice

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

## Configure the GitHub MCP server

**Register** the official, hosted GitHub MCP server, using a `gh` token you already have:

```
claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --header "Authorization: Bearer $(gh auth token)"
```

`file: lab/mcp-config/github.mcp.json` is the same config as a file, `$GITHUB_TOKEN`
substituted from your environment instead of inline.

## Open a real pull request, then close it

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

You asked the same question twice and watched a guess turn into a real, sourced answer.
You watched an agent open a real pull request through a real protocol, and watched a
human, not the agent, decide whether it merged. MCP adds reach. Module 6 is where you build
the gate that MCP servers themselves need to respect, the same permission-boundary caution
already flagged in this chapter's reading.

##### Reading List

- [Model Context Protocol specification](https://modelcontextprotocol.io)
- [HashiCorp Terraform MCP server](https://github.com/hashicorp/terraform-mcp-server)
- [GitHub MCP server](https://github.com/github/github-mcp-server)

##### Search Keywords

- Model Context Protocol, MCP server, MCP client
- terraform-mcp-server, github-mcp-server
- claude mcp add, mcp tool call
- stale training data, live lookup

##### Re-verify

`lab/run.sh` checks the parts of this lab that don't need live credentials: the Terraform
MCP Docker image pulls and responds, the MCP config files are valid JSON, and the captured
evidence files show the real shape this lab depends on (a low-confidence guess, a real MCP
tool citation, a PR that opened then closed without merging).

```
cd modules/module-05-mcp-tool-layer/lab
./run.sh
```
