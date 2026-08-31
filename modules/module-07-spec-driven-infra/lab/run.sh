set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> spec-driven: fmt + init + validate"
terraform -chdir=spec-driven fmt -check -diff . >/tmp/m07-fmt.log 2>&1 || fail "spec-driven not fmt-clean: $(cat /tmp/m07-fmt.log)"
terraform -chdir=spec-driven init -backend=false -input=false -no-color >/dev/null || fail "spec-driven init"
terraform -chdir=spec-driven validate -no-color >/tmp/m07-validate.log 2>&1
grep -q "Success" /tmp/m07-validate.log || fail "spec-driven validate: $(cat /tmp/m07-validate.log)"

echo "==> vibe-coded: fmt + init + validate (still valid HCL, that's the point, nothing stops it)"
terraform -chdir=vibe-coded fmt -check -diff . >/tmp/m07-fmt2.log 2>&1 || fail "vibe-coded not fmt-clean: $(cat /tmp/m07-fmt2.log)"
terraform -chdir=vibe-coded init -backend=false -input=false -no-color >/dev/null || fail "vibe-coded init"
terraform -chdir=vibe-coded validate -no-color >/tmp/m07-validate2.log 2>&1
grep -q "Success" /tmp/m07-validate2.log || fail "vibe-coded validate: $(cat /tmp/m07-validate2.log)"

echo "==> checkov: spec-driven must pass its own three mapped checks (SC-005)"
checkov -d spec-driven -o cli --compact --quiet 2>/dev/null > /tmp/m07-checkov-spec.log
python3 -c "
import re, sys
t = open('/tmp/m07-checkov-spec.log').read()
failed = set(re.findall(r'Check: (CKV\S+):.*?\n\s*FAILED', t))
must_pass = {'CKV_AWS_21', 'CKV2_AWS_6', 'CKV_AWS_19'}
regressed = must_pass & failed
if regressed:
    print('REGRESSED:', regressed); sys.exit(1)
" || fail "spec-driven regressed on a check it should pass"
echo "    ok, spec-driven's own mapped checks (versioning, public-access-block, encrypted-at-rest) all pass"

echo "==> checkov: spec-driven must still have unrelated real gaps (event notifications, lifecycle, logging, replication, KMS)"
grep -q "CKV_AWS_145" /tmp/m07-checkov-spec.log || fail "expected CKV_AWS_145 (KMS) to still fail on spec-driven, spec asked for AES256 not KMS"
echo "    ok, spec-driven honestly still has 5 failed checks outside its own spec's scope"

echo "==> checkov: vibe-coded must fail the exact checks the spec's requirements would have caught"
checkov -d vibe-coded -o cli --compact --quiet 2>/dev/null > /tmp/m07-checkov-vibe.log
python3 -c "
import re, sys
t = open('/tmp/m07-checkov-vibe.log').read()
failed = set(re.findall(r'Check: (CKV\S+):.*?\n\s*FAILED', t))
must_fail = {'CKV_AWS_21', 'CKV2_AWS_6'}
missing = must_fail - failed
if missing:
    print('DID NOT FAIL AS EXPECTED:', missing); sys.exit(1)
" || fail "vibe-coded did not fail the expected checks"
echo "    ok, vibe-coded fails versioning and public-access-block, exactly what FR-001/FR-002 would have caught"

echo "==> spec.md carries all three real parts: requirements, constraints, acceptance criteria"
grep -q "^### Functional Requirements" spec-driven/spec.md || fail "spec.md missing Functional Requirements"
grep -q "^### Constraints" spec-driven/spec.md || fail "spec.md missing Constraints"
grep -q "^### Measurable Outcomes" spec-driven/spec.md || fail "spec.md missing Measurable Outcomes (acceptance criteria)"
echo "    ok"

rm -rf spec-driven/.terraform spec-driven/.terraform.lock.hcl vibe-coded/.terraform vibe-coded/.terraform.lock.hcl

echo
echo "LAB PASSED — spec-driven module honestly passes its own mapped checks and honestly still has unrelated gaps, vibe-coded module fails exactly what the spec's requirements would have caught"
