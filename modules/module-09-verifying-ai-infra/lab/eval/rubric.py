#!/usr/bin/env python3
"""Deterministic rubric: does this Terraform output tag every S3 bucket the way
M04's convention requires? No model involved, plain text parsing, exit 0 or 1."""
import re
import sys

REQUIRED_TAGS = ["Environment", "Owner", "ManagedBy"]


def find_bucket_blocks(text):
    blocks = []
    for match in re.finditer(r'resource\s+"aws_s3_bucket"\s+"([^"]+)"\s*\{', text):
        name = match.group(1)
        start = match.end()
        depth = 1
        i = start
        while depth > 0 and i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        blocks.append((name, text[start:i]))
    return blocks


def check(path):
    try:
        text = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        return False, [f"file not found: {path}"]
    blocks = find_bucket_blocks(text)
    if not blocks:
        return False, ["no aws_s3_bucket resource found"]
    violations = []
    for name, body in blocks:
        missing = [t for t in REQUIRED_TAGS if t not in body]
        if missing:
            violations.append(f"aws_s3_bucket.{name}: missing tags {missing}")
    return (not violations), violations


def main():
    if len(sys.argv) != 2:
        print("usage: rubric.py <path-to-terraform-file>", file=sys.stderr)
        return 2

    ok, violations = check(sys.argv[1])
    if ok:
        print(f"PASS: every bucket in {sys.argv[1]} carries {REQUIRED_TAGS}")
        return 0
    print(f"FAIL: {sys.argv[1]} does not meet the tagging rubric")
    for v in violations:
        print(" -", v)
    return 1


if __name__ == "__main__":
    sys.exit(main())
