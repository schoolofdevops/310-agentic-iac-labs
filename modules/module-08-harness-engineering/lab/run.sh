set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> starter: real checkov findings (must fail, versioning + public access block missing)"
terraform -chdir=starter init -backend=false -input=false -no-color >/dev/null || fail "starter init"
terraform -chdir=starter validate -no-color >/tmp/m08-validate-starter.log 2>&1
grep -q Success /tmp/m08-validate-starter.log || fail "starter validate"
checkov -d starter --compact --quiet >/tmp/m08-checkov-starter.log 2>&1
grep -q "CKV_AWS_21" /tmp/m08-checkov-starter.log || fail "expected CKV_AWS_21 (versioning) in starter findings"
grep -q "CKV2_AWS_6" /tmp/m08-checkov-starter.log || fail "expected CKV2_AWS_6 (public access block) in starter findings"
echo "    ok"

echo "==> solution: real checkov findings (versioning + public access block must now pass)"
terraform -chdir=solution init -backend=false -input=false -no-color >/dev/null || fail "solution init"
terraform -chdir=solution validate -no-color >/tmp/m08-validate-solution.log 2>&1
grep -q Success /tmp/m08-validate-solution.log || fail "solution validate"
checkov -d solution --compact --quiet >/tmp/m08-checkov-solution.log 2>&1
grep -Eq "CKV_AWS_21:" /tmp/m08-checkov-solution.log && fail "CKV_AWS_21 should no longer be in solution's failed list"
grep -Eq "CKV2_AWS_6:" /tmp/m08-checkov-solution.log && fail "CKV2_AWS_6 should no longer be in solution's failed list"
echo "    ok, honestly still 5 unrelated real findings remain (event notifications, lifecycle, logging, KMS, replication), not this fix's job"

echo "==> hook: must BLOCK a completion claim with no real evidence"
./hooks/verify_claim.sh evidence/unbacked-claim.txt >/tmp/m08-hook-unbacked.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "hook should have blocked the unbacked claim"
grep -q "BLOCK" /tmp/m08-hook-unbacked.log || fail "expected a BLOCK message"
echo "    ok, blocked"

echo "==> hook: must PASS a completion claim backed by real checkov output"
./hooks/verify_claim.sh evidence/backed-claim.txt >/tmp/m08-hook-backed.log 2>&1
CODE=$?
[ "$CODE" -eq 0 ] || fail "hook should have passed the backed claim"
grep -q "PASS" /tmp/m08-hook-backed.log || fail "expected a PASS message"
echo "    ok, passed"

echo "==> starting floci 1.7.0"
docker rm -f m08-floci >/dev/null 2>&1
docker run -d --name m08-floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0 >/dev/null || fail "could not start floci"
for i in $(seq 1 30); do
  curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 || fail "floci never became healthy"

echo "==> apply solution against floci"
terraform -chdir=solution apply -auto-approve -no-color >/tmp/m08-apply.log 2>&1
grep -q "Apply complete" /tmp/m08-apply.log || { tail -20 /tmp/m08-apply.log; fail "apply"; }
echo "    ok"

echo "==> destroy"
terraform -chdir=solution destroy -auto-approve -no-color >/tmp/m08-destroy.log 2>&1
grep -q "Destroy complete" /tmp/m08-destroy.log || { tail -20 /tmp/m08-destroy.log; fail "destroy"; }
docker rm -f m08-floci >/dev/null 2>&1
echo "    ok"

rm -rf starter/.terraform starter/.terraform.lock.hcl solution/.terraform solution/.terraform.lock.hcl

echo
echo "LAB PASSED -- starter fails on versioning + public access block, solution fixes both and honestly still has 5 unrelated findings, hook blocks an unbacked claim and passes a backed one, solution applies and destroys cleanly on floci 1.7.0"
