#!/usr/bin/env python3
"""Deterministic CIDR-overlap checker for this repo's multi-environment VPC module.

Reads vpc_cidr out of every envs/*/terraform.tfvars under the given directory and
flags any pairwise overlap. No AI involved: this is plain ipaddress arithmetic, run
by the skill every time an environment's CIDR is added or changed, so a collision is
caught before terraform apply ever runs, not after two environments fight over the
same address space in a real VPC peering setup.
"""
import ipaddress
import re
import sys
from pathlib import Path

CIDR_RE = re.compile(r'vpc_cidr\s*=\s*"([^"]+)"')


def find_cidrs(envs_dir):
    cidrs = {}
    for tfvars in sorted(Path(envs_dir).glob("*/terraform.tfvars")):
        env = tfvars.parent.name
        text = tfvars.read_text()
        m = CIDR_RE.search(text)
        if not m:
            print(f"WARN: no vpc_cidr found in {tfvars}", file=sys.stderr)
            continue
        cidrs[env] = ipaddress.ip_network(m.group(1))
    return cidrs


def find_overlaps(cidrs):
    envs = list(cidrs.items())
    conflicts = []
    for i in range(len(envs)):
        for j in range(i + 1, len(envs)):
            name_a, net_a = envs[i]
            name_b, net_b = envs[j]
            if net_a.overlaps(net_b):
                conflicts.append((name_a, net_a, name_b, net_b))
    return conflicts


def main():
    if len(sys.argv) != 2:
        print("usage: check_cidr_overlap.py <envs-dir>", file=sys.stderr)
        return 2

    cidrs = find_cidrs(sys.argv[1])
    if len(cidrs) < 2:
        print(f"OK: only {len(cidrs)} environment(s) found, nothing to compare")
        return 0

    conflicts = find_overlaps(cidrs)
    if conflicts:
        print("CIDR OVERLAP DETECTED:")
        for name_a, net_a, name_b, net_b in conflicts:
            print(f"  {name_a} ({net_a}) overlaps {name_b} ({net_b})")
        return 1

    print("OK: no CIDR overlap across", ", ".join(sorted(cidrs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
