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
