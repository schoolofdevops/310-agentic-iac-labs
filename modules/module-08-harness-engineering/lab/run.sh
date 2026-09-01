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

echo "==> test-first: RED before the fix exists"
rm -rf /tmp/m08-tdd-red
cp -r tdd /tmp/m08-tdd-red
(cd /tmp/m08-tdd-red && terraform init -backend=false -input=false >/dev/null 2>&1)
/tmp/m08-tdd-red/test_encryption.sh >/tmp/m08-tdd-red.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "encryption test should be RED before the fix"
grep -q "RED:" /tmp/m08-tdd-red.log || fail "expected a RED message"
grep -q "CKV_AWS_145" /tmp/m08-tdd-red.log || fail "RED must fail for the right reason, CKV_AWS_145"
echo "    ok, red for the right reason"

echo "==> test-first: GREEN after the minimal fix"
cp -r tdd/solution/main.tf /tmp/m08-tdd-red/main.tf
rm -rf /tmp/m08-tdd-red/.terraform /tmp/m08-tdd-red/.terraform.lock.hcl
(cd /tmp/m08-tdd-red && terraform init -backend=false -input=false >/dev/null 2>&1)
/tmp/m08-tdd-red/test_encryption.sh >/tmp/m08-tdd-green.log 2>&1
CODE=$?
[ "$CODE" -eq 0 ] || fail "encryption test should be GREEN after the fix"
grep -q "GREEN:" /tmp/m08-tdd-green.log || fail "expected a GREEN message"
echo "    ok, green"
rm -rf /tmp/m08-tdd-red

echo "==> root-cause debugging: the broken endpoint_url must fail validate"
terraform -chdir=debug init -backend=false -input=false -no-color >/dev/null 2>&1
terraform -chdir=debug validate -no-color >/tmp/m08-debug-broken.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "debug/main.tf should fail validate, it uses endpoint_url"
grep -q "endpoint_url" /tmp/m08-debug-broken.log || fail "expected the real endpoint_url error"
echo "    ok, real symptom reproduced"

echo "==> root-cause debugging: the real fix (endpoints{} block) must pass validate"
terraform -chdir=debug/solution init -backend=false -input=false -no-color >/dev/null || fail "debug solution init"
terraform -chdir=debug/solution validate -no-color >/tmp/m08-debug-fixed.log 2>&1
grep -q Success /tmp/m08-debug-fixed.log || fail "debug/solution should validate cleanly"
echo "    ok, root cause fixed"

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
echo "    ok"

echo "==> apply + destroy the root-cause-fixed debug module against floci, proof it actually works"
terraform -chdir=debug/solution apply -auto-approve -no-color >/tmp/m08-debug-apply.log 2>&1
grep -q "Apply complete" /tmp/m08-debug-apply.log || { tail -20 /tmp/m08-debug-apply.log; fail "debug apply"; }
terraform -chdir=debug/solution destroy -auto-approve -no-color >/tmp/m08-debug-destroy.log 2>&1
grep -q "Destroy complete" /tmp/m08-debug-destroy.log || { tail -20 /tmp/m08-debug-destroy.log; fail "debug destroy"; }
echo "    ok"

docker rm -f m08-floci >/dev/null 2>&1

rm -rf starter/.terraform starter/.terraform.lock.hcl solution/.terraform solution/.terraform.lock.hcl \
       tdd/.terraform tdd/.terraform.lock.hcl \
       debug/.terraform debug/.terraform.lock.hcl debug/solution/.terraform debug/solution/.terraform.lock.hcl

echo
echo "LAB PASSED -- verify-before-claiming (hook blocks unbacked, passes backed), test-first (RED for the real reason, GREEN after the minimal fix), root-cause debugging (real endpoint_url symptom reproduced, real endpoints{} fix applies and destroys cleanly on floci 1.7.0)"
