# Capstone — "Propose, Don't Decide"

Every module from M03 to M12 built one piece. This is where they run together, on one
real task, end to end: **the agent proposes, the pipeline decides.**

```
Spec+context → Agent generates → validate (fmt/plan)
  → Trivy + Checkov → OPA/Sentinel → Infracost → plan-diff review
     ↳ failures feed back to the agent
  → HUMAN APPROVAL  ← the only place apply is authorised
  → apply → observe + drift → reopens the spec
```

See `rubric.md` for the full stage-by-stage mapping: what was built, and which module
taught it first.

## Required: Part 1, Tier 1 (Floci)

`lab/tier1-floci/` — the full pipeline against a real Floci-backed AWS emulation. No
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

## Required: Part 2, Tier 2 (Kubernetes)

`lab/tier2-kubernetes/` — the same discipline on a real `kind` cluster: Crossplane v2,
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

## Optional: Part 3, Tier 3 (real AWS)

`lab/tier3-aws-optional/` — the same pipeline, the same Terraform shape, against a
real AWS account. **Read `lab/tier3-aws-optional/README.md` before running anything
here.** It states three things you need to know before your first real `apply`: a
$5 budget alert, EKS's real cost, and a free-plan AWS account's lifecycle. Never
required to complete the capstone. `terraform destroy` is the closing numbered step
in that guide, not a footnote.

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
