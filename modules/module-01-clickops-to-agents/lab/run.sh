set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> starter: fmt check"
terraform -chdir=starter fmt -check -diff >/tmp/m01-fmt.log 2>&1 || fail "starter not fmt-clean: $(cat /tmp/m01-fmt.log)"

echo "==> starter: init + validate"
terraform -chdir=starter init -backend=false -input=false -no-color >/dev/null || fail "starter init"
terraform -chdir=starter validate -no-color >/tmp/m01-validate.log 2>&1
grep -q "Success" /tmp/m01-validate.log || fail "starter validate: $(cat /tmp/m01-validate.log)"

echo "==> starter: plan"
terraform -chdir=starter plan -no-color -input=false >/tmp/m01-plan.log 2>&1 || fail "starter plan: $(cat /tmp/m01-plan.log)"
grep -q "4 to add" /tmp/m01-plan.log || fail "starter plan didn't match expected 4 resources"

echo "==> starter: checkov must FAIL on the hardcoded secret"
checkov -d starter --compact --quiet >/tmp/m01-checkov-starter.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "starter checkov unexpectedly passed, secrets scan should have caught the AWS key"
grep -q "CKV_SECRET_2" /tmp/m01-checkov-starter.log || fail "expected CKV_SECRET_2 finding, got: $(cat /tmp/m01-checkov-starter.log)"
echo "    ok, CKV_SECRET_2 found as expected"

echo "==> solution: fmt + validate + checkov must PASS"
terraform -chdir=solution fmt -check -diff >/tmp/m01-fmt-sol.log 2>&1 || fail "solution not fmt-clean: $(cat /tmp/m01-fmt-sol.log)"
terraform -chdir=solution init -backend=false -input=false -no-color >/dev/null || fail "solution init"
terraform -chdir=solution validate -no-color >/tmp/m01-validate-sol.log 2>&1
grep -q "Success" /tmp/m01-validate-sol.log || fail "solution validate: $(cat /tmp/m01-validate-sol.log)"
checkov -d solution --compact --quiet >/tmp/m01-checkov-sol.log 2>&1 || fail "solution checkov: $(cat /tmp/m01-checkov-sol.log)"
echo "    ok, solution is checkov-clean"

rm -rf starter/.terraform starter/.terraform.lock.hcl solution/.terraform solution/.terraform.lock.hcl

echo
echo "LAB PASSED — starter fails checkov on CKV_SECRET_2 as designed, solution is clean"
