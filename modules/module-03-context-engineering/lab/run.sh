set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> run 1 (no context): fmt + validate"
terraform -chdir=starter fmt -check -diff >/tmp/m03-fmt1.log 2>&1 || fail "starter not fmt-clean: $(cat /tmp/m03-fmt1.log)"
terraform -chdir=starter init -backend=false -input=false -no-color >/dev/null || fail "starter init"
terraform -chdir=starter validate -no-color >/tmp/m03-validate1.log 2>&1
grep -q "Success" /tmp/m03-validate1.log || fail "starter validate: $(cat /tmp/m03-validate1.log)"

echo "==> run 1: checkov must FAIL on the hardcoded secret"
checkov -d starter --compact --quiet >/tmp/m03-checkov1.log 2>&1
[ $? -ne 0 ] || fail "run 1 unexpectedly passed checkov, expected CKV_SECRET_2"
grep -q "CKV_SECRET_2" /tmp/m03-checkov1.log || fail "expected CKV_SECRET_2 in run 1"
echo "    ok, run 1 (no AGENTS.md) fails as expected"

echo "==> run 2 (with context): fmt + validate + checkov must PASS"
terraform -chdir=solution fmt -check -diff >/tmp/m03-fmt2.log 2>&1 || fail "solution not fmt-clean: $(cat /tmp/m03-fmt2.log)"
terraform -chdir=solution init -backend=false -input=false -no-color >/dev/null || fail "solution init"
terraform -chdir=solution validate -no-color >/tmp/m03-validate2.log 2>&1
grep -q "Success" /tmp/m03-validate2.log || fail "solution validate: $(cat /tmp/m03-validate2.log)"
checkov -d solution --compact --quiet >/tmp/m03-checkov2.log 2>&1 || fail "run 2 checkov: $(cat /tmp/m03-checkov2.log)"
echo "    ok, run 2 (with AGENTS.md) is checkov-clean"

echo "==> AGENTS.md structural check"
AF=solution/AGENTS.md
[ -f "$AF" ] || fail "AGENTS.md missing"
grep -qi "provider" "$AF" || fail "AGENTS.md missing provider pins section"
grep -qi "naming" "$AF" || fail "AGENTS.md missing naming convention section"
grep -qi "never" "$AF" || fail "AGENTS.md missing a never-do list"
grep -qi "TF_VAR_" "$AF" || fail "AGENTS.md missing where-secrets-come-from guidance"
echo "    ok, AGENTS.md has all four required sections"

rm -rf starter/.terraform starter/.terraform.lock.hcl solution/.terraform solution/.terraform.lock.hcl

echo
echo "LAB PASSED — run 1 (no context) fails checkov, run 2 (with AGENTS.md) is clean, AGENTS.md is well-formed"
