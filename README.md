# 310 — Agentic Infrastructure as Code: labs

Learner-facing labs for *Agentic Infrastructure as Code: AI Agents for DevOps* (course 310).
Clone this repo to follow along. Course source and full explainers live in a separate,
private authoring repo; this one holds only what you run.

**Status: early build.** Module 1's lab is live and verified. The rest of the course
(M02–M12, capstone) is still in progress, more labs land here as each module ships.

## Quick start

```
# install the pinned tools on your host first, see the course site's Environment Setup page, then:
docker compose -f labs/shared/docker-compose.floci.yml up -d
cd labs/shared/floci-spike && ./run.sh
```

Lab tiers 0–2 cost nothing and need no cloud account. Tier 3 is optional, capstone only.

## What's here

```
labs/shared/                shared lab infrastructure (Floci spike, docker-compose)
modules/module-01-clickops-to-agents/
  LAB.md                    Lab 1: Be the Agent (Tier 0, ~12 min)
  lab/starter/               skeleton you copy and adapt, deliberately fails a checkov scan
  lab/solution/               the fixed version, for after you've tried it yourself
```

## Module 1: Be the Agent

Tier 0, terraform and checkov only, no agent yet, no cloud account. Start with
[`modules/module-01-clickops-to-agents/LAB.md`](modules/module-01-clickops-to-agents/LAB.md).
