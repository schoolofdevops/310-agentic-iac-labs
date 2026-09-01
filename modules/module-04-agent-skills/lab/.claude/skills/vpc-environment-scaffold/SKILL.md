---
name: vpc-environment-scaffold
description: Scaffold or validate this repo's multi-environment VPC module (dev/staging/prod) under vpc/. Use whenever asked to add a new environment, change a VPC CIDR block, or check environments for CIDR overlap before applying.
---

# VPC environment conventions

Apply these rules whenever working on anything under `vpc/`.

## Shape

- The shared module lives at `vpc/modules/vpc`. Every environment is a thin caller under
  `vpc/envs/<name>/`, passing `vpc_cidr`, `az_count`, `public_subnet_cidrs`,
  `private_subnet_cidrs`, `nat_strategy` through `terraform.tfvars`.
- **dev**: 1 AZ, `nat_strategy = "single"`. Cheapest possible failure mode, acceptable for
  throwaway work nobody's on call for.
- **staging**: 2 AZs, `nat_strategy = "single"`. Enough spread to catch AZ-specific bugs
  before prod. NAT redundancy isn't worth the extra cost here, staging going dark for a few
  minutes during a NAT replacement is not an incident.
- **prod**: 3 AZs, `nat_strategy = "per_az"`. One NAT gateway per AZ, on purpose, so a NAT
  outage in one AZ never takes the other two down with it. This is the one place the extra
  NAT gateway cost is worth it.
- Every environment's `vpc_cidr` is a distinct `/16` out of the `10.0.0.0/8` block this repo
  reserves for VPCs. Don't invent a CIDR outside that range without a documented reason.

## Before adding or changing any environment's `vpc_cidr`

**Always run the bundled overlap checker first**, against the real `vpc/envs` directory
this task is working in:

```
python3 <this-skill-dir>/scripts/check_cidr_overlap.py <repo>/vpc/envs
```

A non-zero exit means a real CIDR collision between two environments. Do not proceed to
`terraform plan` or `apply` until it exits 0. This is deterministic arithmetic, not a
judgment call, run it, don't reason your way past it.

## When scaffolding a brand new environment

1. Create `vpc/envs/<name>/` with `main.tf` (a `module "vpc"` block calling
   `../../modules/vpc`, matching the shape of the three existing environments exactly),
   `variables.tf` (same five variables as every other environment), `terraform.tfvars`
   (the environment's real values), and `provider.tf` (copy verbatim from
   `labs/shared/floci-spike/provider.tf`, this repo's canonical Tier 1 stub).
2. Pick `az_count` and `nat_strategy` by asking what this environment is actually for, not
   by copying an existing environment's numbers. A short-lived preview environment behaves
   like dev. A second production region behaves like prod.
3. Run the overlap checker before anything else touches this environment.
4. Run `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` from
   inside the new environment's directory.
