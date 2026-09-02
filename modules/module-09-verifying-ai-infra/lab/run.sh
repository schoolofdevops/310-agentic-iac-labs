#!/usr/bin/env bash
# M09 Tier-1 lab validation. Exits non-zero on any pass-criterion failure.
# Reproduces the opening demo's real numbers against the real floci-spike module, confirms
# the starter module fails at trivy, the solution passes fmt/trivy/checkov/conftest, and
# the assembled pipeline.sh blocks the starter and passes the solution end to end.
set -uo pipefail
cd "$(dirname "$0")"
export PATH="/tmp/checkov-venv/bin:$PATH"
ENDPOINT="${ENDPOINT:-http://localhost:4566}"
fail(){ echo "FAIL: $*" >&2; exit 1; }

for tool in trivy checkov conftest; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not on PATH"
done

REPO_ROOT="$(cd ../../.. && pwd)"

echo "==> reproduce the opening demo against the real floci-spike module"
SPIKE="$REPO_ROOT/labs/shared/floci-spike"
[ -d "$SPIKE" ] || fail "floci-spike module not found at $SPIKE"
TRIVY_OUT=$(trivy config --quiet --severity HIGH,CRITICAL "$SPIKE" 2>&1)
TRIVY_TOTAL=$(echo "$TRIVY_OUT" | grep -oE "Failures: [0-9]+" | grep -oE "[0-9]+" | python3 -c "import sys; print(sum(int(l) for l in sys.stdin))")
[ "$TRIVY_TOTAL" = "7" ] || fail "expected trivy total 7, got $TRIVY_TOTAL"
CHECKOV_OUT=$(checkov -d "$SPIKE" --compact --quiet --framework terraform --skip-download 2>&1)
echo "$CHECKOV_OUT" | grep -q "Failed checks: 25" || fail "expected checkov 25 failed checks: $(echo "$CHECKOV_OUT" | grep 'scan results' -A2)"
echo "    ok, trivy 7 / checkov 25, matches labs/shared/floci-spike/RESULTS.md"

echo "==> starter module: both scanners must find real, disagreeing findings"
trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL module >/dev/null 2>&1
[ "$?" -ne 0 ] || fail "starter should have HIGH/CRITICAL trivy findings"
checkov -d module --compact --quiet --framework terraform --skip-download >/dev/null 2>&1
[ "$?" -ne 0 ] || fail "starter should have checkov findings"
STARTER_CHECKOV_OUT=$(checkov -d module --compact --quiet --framework terraform --skip-download 2>&1)
echo "$STARTER_CHECKOV_OUT" | grep -q "CKV_AWS_144" \
  || fail "expected CKV_AWS_144 (cross-region replication) in starter's checkov findings, the checkov-only example"
echo "    ok, starter fails both scanners, CKV_AWS_144 present as the checkov-only example"

echo "==> conftest: starter must FAIL (reports bucket has no Owner tag), solution must PASS"
rm -rf module/.terraform module/.terraform.lock.hcl solution/.terraform solution/.terraform.lock.hcl
terraform -chdir=module init -backend=false -input=false -no-color >/dev/null || fail "module init"
terraform -chdir=module plan -no-color -out=/tmp/m09-run-plan.bin -var="endpoint=${ENDPOINT}" >/tmp/m09-run-plan.log 2>&1 || { cat /tmp/m09-run-plan.log; fail "module plan"; }
terraform -chdir=module show -json /tmp/m09-run-plan.bin > /tmp/m09-run-plan.json
conftest test --policy policy /tmp/m09-run-plan.json >/tmp/m09-conftest-starter.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "conftest should have failed on starter (reports has no Owner tag)"
grep -q "aws_s3_bucket.reports has no Owner tag" /tmp/m09-conftest-starter.log || fail "expected the specific Owner-tag message: $(cat /tmp/m09-conftest-starter.log)"

terraform -chdir=solution init -backend=false -input=false -no-color >/dev/null || fail "solution init"
terraform -chdir=solution plan -no-color -out=/tmp/m09-run-plan-sol.bin -var="endpoint=${ENDPOINT}" >/tmp/m09-run-plan-sol.log 2>&1 || { cat /tmp/m09-run-plan-sol.log; fail "solution plan"; }
terraform -chdir=solution show -json /tmp/m09-run-plan-sol.bin > /tmp/m09-run-plan-sol.json
conftest test --policy policy /tmp/m09-run-plan-sol.json || fail "conftest should have passed on solution"
echo "    ok, conftest fails on starter, passes on solution"

echo "==> assembled pipeline.sh: must BLOCK starter, must PASS solution"
ENDPOINT="$ENDPOINT" ./pipeline.sh module >/tmp/m09-pipeline-starter.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "pipeline.sh should have blocked the starter module"
grep -q "BLOCKED" /tmp/m09-pipeline-starter.log || fail "expected a BLOCKED message: $(cat /tmp/m09-pipeline-starter.log)"

ENDPOINT="$ENDPOINT" ./pipeline.sh solution >/tmp/m09-pipeline-solution.log 2>&1 || { cat /tmp/m09-pipeline-solution.log; fail "pipeline.sh should have passed the solution"; }
grep -q "PIPELINE PASSED" /tmp/m09-pipeline-solution.log || fail "expected PIPELINE PASSED: $(cat /tmp/m09-pipeline-solution.log)"
echo "    ok, pipeline.sh blocks starter, passes solution"

rm -rf module/.terraform module/.terraform.lock.hcl module/terraform.tfstate* \
       solution/.terraform solution/.terraform.lock.hcl solution/terraform.tfstate*

echo "==> Step 6: eval rubric"
python3 eval/rubric.py eval/fixture-bad.tf && fail "rubric should have rejected fixture-bad.tf"
python3 eval/rubric.py eval/fixture-good.tf || fail "rubric should have accepted fixture-good.tf"
echo "eval rubric: PASS"

echo
echo "LAB PASSED: opening demo reproduced (trivy 7 / checkov 25), starter fails both scanners"
echo "and conftest, solution passes everything, assembled pipeline.sh blocks starter and passes solution,"
echo "and the eval rubric rejects fixture-bad.tf and accepts fixture-good.tf"
