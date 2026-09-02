# Capstone rubric: the pipeline diagram, staged

Every stage of the course thesis pipeline (`CLAUDE.md`), mapped to what this capstone
actually built and which module taught it first.

```
Spec+context → Agent generates → validate (fmt/plan)
  → Trivy + Checkov → OPA/Sentinel → Infracost → plan-diff review
     ↳ failures feed back to the agent
  → HUMAN APPROVAL  ← the only place apply is authorised
  → apply → observe + drift → reopens the spec
```

| Stage | Taught in | Built in the capstone as |
|---|---|---|
| Spec | M07 | `spec.md`, requirements/constraints/acceptance-criteria for the storage-and-config task |
| Context | M03 | `AGENTS.md` |
| Skill | M04 | `.claude/skills/capstone-conventions/SKILL.md` |
| Agent generates | M01, M02 | `lab/tier1-floci/starter/main.tf` and `solution/main.tf` |
| validate (fmt/plan) | M01 | Stage 1 of `pipeline.sh` |
| Trivy + Checkov | M09 | Stages 2-3 of `pipeline.sh`, real findings on `starter`, real pass on `solution`'s own spec'd scope |
| OPA/Sentinel | M09 | Stage 4, `policy/tags.rego`, real deny on `starter`, real pass on `solution` |
| plan-diff review / blast radius | M06 | Stage 5, `blast_radius_gate.sh` |
| Infracost | M09 | Not exercised here for real (same honest gap M07/M08 reported: no non-interactive Infracost auth in this environment); the pipeline names the stage and where it would sit |
| HUMAN APPROVAL | M06, M11, M12 (step 4/5) | Stage 6, `CAPSTONE_HUMAN_APPROVED=1`, the only thing that unblocks `apply` |
| apply | all Tier 1/2 modules | Real Floci apply (`lab/tier1-floci/run.sh`), real Kubernetes apply via a merged, CI-gated PR and Argo CD (`lab/tier2-kubernetes/run.sh`) |
| observe + drift, reopens the spec | M10, M11, M12 | Real drift demo: `aws s3api put-bucket-versioning ... Suspended`, caught on the next `terraform plan`; Argo CD's own self-heal loop, taught in M11, is the Kubernetes-side equivalent |
| MCP (context on demand) | M05 | Named in `AGENTS.md`/`README.md`; the same Terraform MCP server from M05 is available to the agent generating this module, optional, not required for the pipeline itself |
| Harness (assembled discipline) | M08 | The whole of `pipeline.sh` is the harness: skill + gate + human approval, assembled, not separate lessons |
| GitOps loop | M10, M11 | `lab/tier2-kubernetes/`: real `kind`, real Crossplane v2, real CI-gated merged PR, real Argo CD, real Synced/Healthy state |
| Loop / step 6 | M12 | Not attempted here on purpose. The capstone runs step 4/5 (gated apply, then unattended reconcile after a human merge), the same ceiling M11/M12 taught as the safe default |

**No stage on this list is untested prose.** Every row above that says "real" was run in
this environment and its output captured in `lab/tier1-floci/run.sh` and
`lab/tier2-kubernetes/run.sh`, both of which exit non-zero on any regression.
