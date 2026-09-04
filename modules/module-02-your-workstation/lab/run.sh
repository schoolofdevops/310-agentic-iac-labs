set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> pinned-tool prerequisites reachable"
terraform version >/dev/null 2>&1 || fail "terraform not on PATH"
checkov --version >/dev/null 2>&1 || fail "checkov not on PATH"
docker info >/dev/null 2>&1 || fail "docker not reachable"
echo "    ok"

echo "==> step1-suggested: fmt + init + validate (fixed version, path.module bug removed)"
terraform -chdir=solution/step1-suggested fmt -check -diff >/tmp/m02-fmt1.log 2>&1 || fail "step1 not fmt-clean: $(cat /tmp/m02-fmt1.log)"
terraform -chdir=solution/step1-suggested init -backend=false -input=false -no-color >/dev/null || fail "step1 init"
terraform -chdir=solution/step1-suggested validate -no-color >/tmp/m02-validate1.log 2>&1
grep -q "Success" /tmp/m02-validate1.log || fail "step1 validate: $(cat /tmp/m02-validate1.log)"
echo "    ok"

echo "==> step2-drafted: fmt + init + validate"
terraform -chdir=solution/step2-drafted fmt -check -diff >/tmp/m02-fmt2.log 2>&1 || fail "step2 not fmt-clean: $(cat /tmp/m02-fmt2.log)"
terraform -chdir=solution/step2-drafted init -backend=false -input=false -no-color >/dev/null || fail "step2 init"
terraform -chdir=solution/step2-drafted validate -no-color >/tmp/m02-validate2.log 2>&1
grep -q "Success" /tmp/m02-validate2.log || fail "step2 validate: $(cat /tmp/m02-validate2.log)"
echo "    ok"

echo "==> both must be checkov-clean (no built-in coverage for these resource types, same gap as Lab 1)"
checkov -d solution/step1-suggested --compact --quiet >/tmp/m02-ck1.log 2>&1 || fail "step1 checkov: $(cat /tmp/m02-ck1.log)"
checkov -d solution/step2-drafted --compact --quiet >/tmp/m02-ck2.log 2>&1 || fail "step2 checkov: $(cat /tmp/m02-ck2.log)"
echo "    ok"

echo "==> the two files must genuinely differ (real finding: same intent, same model, two runs diverge)"
DIFF_LINES=$(diff solution/step1-suggested/main.tf solution/step2-drafted/main.tf | wc -l | tr -d ' ')
[ "$DIFF_LINES" -gt 0 ] || fail "step1 and step2 are identical, the lab's core finding no longer holds"
echo "    ok, $DIFF_LINES diff lines"

rm -rf solution/step1-suggested/.terraform solution/step1-suggested/.terraform.lock.hcl
rm -rf solution/step2-drafted/.terraform solution/step2-drafted/.terraform.lock.hcl

echo
echo "LAB PASSED — step1-suggested and step2-drafted both validate and pass checkov, and genuinely differ from each other"
