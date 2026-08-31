#!/usr/bin/env bash
# The assembled M09 pipeline: cheap checks first, expensive human attention last.
# scan (trivy, checkov) -> policy (conftest) -> cost (infracost, if configured) -> apply.
# Exits non-zero on the FIRST failing stage, same contract as every gate in this course.
set -uo pipefail
cd "$(dirname "$0")"
TARGET="${1:-module}"
ENDPOINT="${ENDPOINT:-http://localhost:4566}"

echo "==> stage 1/5: fmt + validate"
terraform -chdir="$TARGET" fmt -check -diff || { echo "BLOCKED at fmt"; exit 1; }
terraform -chdir="$TARGET" validate -no-color || { echo "BLOCKED at validate"; exit 1; }

echo "==> stage 2/5: trivy"
trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL "$TARGET" || { echo "BLOCKED at trivy"; exit 1; }
echo "    trivy: no HIGH/CRITICAL findings"

echo "==> stage 3/5: checkov"
# CKV2_AWS_62 / CKV2_AWS_61 / CKV_AWS_144 are a reviewed, documented exception for this lab
# bucket (see the comment in solution/main.tf). --skip-check is the flag that actually works
# for this; inline #checkov:skip comments were tested and did not suppress these findings.
checkov -d "$TARGET" --compact --quiet --framework terraform --skip-download \
  --skip-check CKV2_AWS_62,CKV2_AWS_61,CKV_AWS_144 || { echo "BLOCKED at checkov"; exit 1; }
echo "    checkov: no unreviewed findings"

echo "==> stage 4/5: conftest (org policy: every aws_s3_bucket needs tags.Owner)"
terraform -chdir="$TARGET" plan -no-color -out=/tmp/m09-pipeline-plan.bin -var="endpoint=${ENDPOINT}" >/tmp/m09-pipeline-plan.log 2>&1 || { cat /tmp/m09-pipeline-plan.log; echo "BLOCKED at plan"; exit 1; }
terraform -chdir="$TARGET" show -json /tmp/m09-pipeline-plan.bin > /tmp/m09-pipeline-plan.json
conftest test --policy policy /tmp/m09-pipeline-plan.json || { echo "BLOCKED at conftest"; exit 1; }

echo "==> stage 5/5: cost gate (infracost)"
if [ -n "${INFRACOST_API_KEY:-}" ]; then
  infracost breakdown --path "$TARGET" --format json > /tmp/m09-infracost.json 2>/tmp/m09-infracost.err
  if [ $? -ne 0 ]; then
    cat /tmp/m09-infracost.err
    echo "BLOCKED at cost stage (infracost error)"
    exit 1
  fi
  echo "    infracost ran, see /tmp/m09-infracost.json for the real estimate"
else
  echo "    SKIPPED: no INFRACOST_API_KEY set. Run 'infracost auth login' once (free, no card)"
  echo "    to enable this stage for real. See reading/reference.md."
fi

echo
echo "PIPELINE PASSED for $TARGET: every stage that could run, ran for real and passed"
