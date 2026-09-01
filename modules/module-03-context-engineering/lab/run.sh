set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> reduce: --compact must cut checkov output by a real, large margin"
FLOCI_SPIKE="../../../labs/shared/floci-spike"
[ -d "$FLOCI_SPIKE" ] || fail "floci-spike dir not found at $FLOCI_SPIKE"
checkov -d "$FLOCI_SPIKE" --framework terraform >/tmp/m03-verbose.log 2>/dev/null
checkov -d "$FLOCI_SPIKE" --framework terraform --compact --quiet >/tmp/m03-compact.log 2>/dev/null
VERBOSE_SIZE=$(wc -c </tmp/m03-verbose.log)
COMPACT_SIZE=$(wc -c </tmp/m03-compact.log)
[ "$VERBOSE_SIZE" -gt 0 ] || fail "verbose checkov output was empty"
[ "$COMPACT_SIZE" -gt 0 ] || fail "compact checkov output was empty"
REDUCTION=$(( (VERBOSE_SIZE - COMPACT_SIZE) * 100 / VERBOSE_SIZE ))
[ "$REDUCTION" -ge 50 ] || fail "expected at least 50% reduction, got ${REDUCTION}% (verbose=$VERBOSE_SIZE compact=$COMPACT_SIZE)"
echo "    ok, verbose=$VERBOSE_SIZE bytes, compact=$COMPACT_SIZE bytes, ${REDUCTION}% smaller"

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
echo "LAB PASSED — reduce: compact cuts checkov output by a real, large margin; retain: run 1 (no context) fails checkov, run 2 (with AGENTS.md) is clean, AGENTS.md is well-formed. Route (the fresh-session STATE.md exercise) is hands-on only, not scripted here, see LAB.md."
