# Capstone Project: Ship Infrastructure Through a Propose-Verify-Approve-Apply Pipeline

In this project, you will run one real infrastructure change through a full pipeline: an
agent proposes it, Trivy, Checkov, and OPA verify it, a human approves it, and only then does
it apply for real. **The agent proposes, the pipeline decides.**

```
Spec+context → Agent generates → validate (fmt/plan)
  → Trivy + Checkov → OPA/Sentinel → Infracost → plan-diff review
     ↳ failures feed back to the agent
  → HUMAN APPROVAL  ← the only place apply is authorised
  → apply → observe + drift → reopens the spec
```

**What you're building, at a glance:**

- A storage and config module (S3 + DynamoDB) that fails the pipeline on purpose, then a
  fixed version that clears every stage
- A real human-approval gate that blocks `apply` until `CAPSTONE_HUMAN_APPROVED=1` is set
- Real drift, introduced by hand against the emulated S3 API, caught on the next `plan`
- A real CI-gated pull request on Kubernetes infrastructure, merged, and reconciled onto a
  real `kind` cluster by Argo CD, unattended
- Optionally, the same pipeline run once against a real AWS account

See `rubric.md` for the full stage-by-stage mapping: what was built, and which module
taught it first. Or click through it interactively:
[Pipeline Tracer](explainer/sim/pipeline-tracer-sim.html), every stage, every module,
one screen.

## Stage 1: Run the pipeline against Floci (Tier 1, required)

`lab/tier1-floci/`: the full pipeline against a real Floci-backed AWS emulation. No
cloud account, no cost.

```
cd lab/tier1-floci
./run.sh
```

Real, verified: the `starter` module fails Trivy, Checkov, and the capstone's own
tags policy for real, and the pipeline stops before human approval. The `solution`
module clears every stage, requires `CAPSTONE_HUMAN_APPROVED=1` to unblock `apply`,
applies four real resources against Floci, has real drift introduced directly against
the emulated S3 API and catches it on the next `plan`, then tears down with a real
`terraform destroy`.

## Stage 2: Run the pipeline against a real cluster (Tier 2, required)

`lab/tier2-kubernetes/`: the same discipline on a real `kind` cluster: Crossplane v2,
a real CI-gated pull request, a real merge, a real Argo CD reconciling the cluster
from that merge, unattended.

```
cd lab/tier2-kubernetes
./run.sh
```

Real, verified: [PR #3 on `310-agentic-iac-labs`](https://github.com/schoolofdevops/310-agentic-iac-labs/pull/3)
failed real CI on a real missing field, was fixed, went green, and was merged for
real. Argo CD, pointed at that merged repo path, reached real `Synced`/`Healthy`
state and composed a real `ConfigMap` with the merged content. Numbered teardown
removes the Argo CD application and deletes the cluster.

## Stage 3: Run the pipeline against real AWS (Tier 3, optional)

`lab/tier3-aws-optional/`: the same pipeline, the same Terraform module, against a
real AWS account. **Read `lab/tier3-aws-optional/README.md` before running anything
here.** It states three things you need to know before your first real `apply`: a
$5 budget alert, EKS's real cost, and a free-plan AWS account's lifecycle. Never
required to complete the capstone. `terraform destroy` is the closing numbered step
in that guide, not a footnote.

## Validation

Each stage above runs its own `run.sh`, and each one is the real proof that stage worked, not
a formality:

- Stage 1's `run.sh` fails the starter module on Trivy/Checkov/tags, then applies, drifts, and
  destroys the solution module for real against Floci
- Stage 2's `run.sh` confirms the real merged PR and Argo CD's real `Synced`/`Healthy` state on
  a real `kind` cluster
- Stage 3, if you run it, ends in its own guide's numbered `terraform destroy`, confirmed
  against your real AWS account

Run all three (Stage 3 optional) before you consider the capstone done.

## Summary

What you built:

- One real spec, deliberately imperfect, run through Trivy, Checkov, and OPA
- A human-approval gate that actually blocks `apply` until a human sets the flag
- Real drift, introduced on purpose, caught by the pipeline on its own
- A real PR, real CI, a real merge, and a real unattended GitOps apply on Kubernetes
- Optionally, the same discipline proven once against a real AWS account, then torn down

Twelve modules, one pipeline. Every stage above is a real, independent proof that "the agent
proposes, the pipeline decides" holds up end to end, not just per module.

## The closing exercise

Go back to `modules/module-01-clickops-to-agents/LAB.md`. Find the `notes.md` file
you wrote at the end of Lab 1, the three-line note on what you'd hand to a machine
without watching, what you'd still watch yourself, and why.

Open it again. Add a second, dated entry below your original one. After building
context (M03), a skill (M04), a live connection (M05), a real gate (M06), a spec
(M07), a full harness (M08), a real pipeline (M09), a real cluster (M10), a real
GitOps loop (M11), and a real stopping condition (M12):

- What changed about your answer?
- What's still true, word for word, from Lab 1?
- If it's the same split you wrote in Lab 1, why? If it moved, what specifically
  earned that move, not a general feeling that "the tools got better"?

There's no required answer. The point of the exercise was never to get the split
right the first time. It was to have something written down to compare against,
honestly, after doing the work that either does or doesn't justify moving it.
