#!/usr/bin/env bash
# RED-GREEN test for one real check: CKV_AWS_145 (S3 bucket encrypted with KMS by default).
# Run this BEFORE writing the fix. It must fail, and fail for this specific reason.
set -uo pipefail
cd "$(dirname "$0")"

OUT=$(checkov -d . --compact --quiet --skip-download --check CKV_AWS_145 2>&1)
CODE=$?

if [ "$CODE" -eq 0 ] && echo "$OUT" | grep -Eq "Failed checks: 0"; then
  echo "GREEN: aws_s3_bucket.artifacts is encrypted with a default KMS key"
  exit 0
fi

echo "RED: aws_s3_bucket.artifacts is not encrypted yet"
echo "$OUT" | grep -A2 "CKV_AWS_145" || echo "$OUT"
exit 1
