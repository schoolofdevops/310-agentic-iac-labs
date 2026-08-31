---
name: terraform-module-conventions
description: House rules for any Terraform module written against this repo's AWS-shaped provider (Floci or real AWS). Use whenever asked to write, generate, or extend a Terraform module for an AWS resource.
---

# Terraform module conventions

Apply these rules to every Terraform module in this repo, whether or not the request
mentions them by name. They exist so a reviewer never has to ask for the same three
fixes twice, on every module, from every author, human or agent.

## Provider pins

- Pin the `aws` provider to `~> 6.0`, exactly as declared in
  `labs/shared/floci-spike/provider.tf`. Never leave a provider version unconstrained
  and never bump the pin without a reason in the commit message.

## Required tags

- Every taggable resource gets a `tags` block with at least `Environment`, `Owner`, and
  `ManagedBy`. A resource with no way to attribute cost or ownership is a resource
  nobody can safely delete later.

## Secrets

- Never a secret in a `default`. Every credential-shaped variable is `sensitive = true`,
  with no default, set via `TF_VAR_<name>` at runtime. This is the same rule Module 1's
  lab teaches by hand, applied here automatically. A scanner catching this after the
  fact is a backstop, not the plan.

## Why this skill exists

Without it, an agent asked for "a small S3 bucket module" produces something that
applies cleanly and fails the first cost or ownership audit: no tags, an unpinned
provider that drifts to whatever version it last saw in training data, and a
credential sitting in a `default` because that was the fastest way to make the plan
work. This skill is the harness catching that class of mistake before a human reviewer
has to.
