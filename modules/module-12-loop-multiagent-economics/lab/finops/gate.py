#!/usr/bin/env python3
"""FinOps gate: fails on resource-count, tag, or instance-type violations, read
straight from `terraform show -json`. No Infracost API key required, this checks
policy, not live pricing."""
import json
import sys

MAX_RESOURCES = 10
REQUIRED_TAGS = ["Environment", "Owner", "ManagedBy"]
ALLOWED_INSTANCE_TYPES = {"t3.micro", "t3.small", "t3.medium"}


def check(plan_path):
    plan = json.load(open(plan_path, encoding="utf-8"))
    resources = plan.get("planned_values", {}).get("root_module", {}).get("resources", [])
    violations = []
    if len(resources) > MAX_RESOURCES:
        violations.append(f"resource count {len(resources)} exceeds max {MAX_RESOURCES}")
    for r in resources:
        values = r.get("values", {}) or {}
        # Tag and instance-type checks only apply to resource types that carry
        # those fields at all. A local_file or null_resource has neither, and
        # is not a FinOps violation for lacking them.
        if "tags" in values:
            tags = values.get("tags") or {}
            missing = [t for t in REQUIRED_TAGS if t not in tags]
            if missing:
                violations.append(f"{r['address']}: missing tags {missing}")
        instance_type = values.get("instance_type")
        if instance_type and instance_type not in ALLOWED_INSTANCE_TYPES:
            violations.append(
                f"{r['address']}: instance_type {instance_type} not in {sorted(ALLOWED_INSTANCE_TYPES)}"
            )
    return violations


if __name__ == "__main__":
    violations = check(sys.argv[1])
    if violations:
        print("FINOPS GATE FAILED:")
        for v in violations:
            print(" -", v)
        sys.exit(1)
    print(f"FinOps gate passed: {sys.argv[1]} within policy.")
    sys.exit(0)
