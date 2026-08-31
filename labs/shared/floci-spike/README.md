# Floci spike — Tier 1 lab foundation

Reproducible verification that the free, no-account AWS emulator can carry the Tier 1 labs.
**Run this before building any Tier 1 lab, and re-run it whenever you bump the pinned Floci version.**

```bash
./run.sh          # start floci, apply, verify, scan, destroy
./run.sh --keep   # leave the stack up for poking around
```

Pass criteria — all must hold:

1. `terraform apply` completes with **21/21 resources**
2. RDS produces a **real, connectable MySQL** with the named database present
3. EC2 produces a **real Amazon Linux 2023 container** with `dnf` available
4. The `aws_ami` data source resolves
5. `terraform destroy` removes everything and leaves **zero orphan containers**
6. Trivy and Checkov both run against the code and disagree (Checkov finds strictly more)

Result of the last run: see `RESULTS.md`.
