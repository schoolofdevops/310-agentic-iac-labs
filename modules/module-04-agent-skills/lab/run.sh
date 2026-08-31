#!/usr/bin/env bash
# M04 Tier-1 lab validation. Exits non-zero on any pass-criterion failure.
set -uo pipefail
cd "$(dirname "$0")"
FLOCI_VERSION="${FLOCI_VERSION:-1.7.0}"
export TF_VAR_artifact_uploader_key="AKIAFAKELABKEY000111"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> starter (no skill): fmt + init + validate + plan"
terraform -chdir=starter fmt -check -diff >/tmp/m04-fmt.log 2>&1 || fail "starter not fmt-clean: $(cat /tmp/m04-fmt.log)"
terraform -chdir=starter init -backend=false -input=false -no-color >/dev/null || fail "starter init"
terraform -chdir=starter validate -no-color >/tmp/m04-validate.log 2>&1
grep -q "Success" /tmp/m04-validate.log || fail "starter validate: $(cat /tmp/m04-validate.log)"
terraform -chdir=starter plan -no-color -input=false >/tmp/m04-plan.log 2>&1 || fail "starter plan: $(cat /tmp/m04-plan.log)"
grep -q "1 to add" /tmp/m04-plan.log || fail "starter plan didn't match expected 1 resource"

echo "==> starter: checkov secrets framework must FAIL on the hardcoded key"
checkov -d starter --framework secrets --compact --quiet >/tmp/m04-checkov-starter.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "starter secrets scan unexpectedly passed"
grep -q "CKV_SECRET_2" /tmp/m04-checkov-starter.log || fail "expected CKV_SECRET_2 finding, got: $(cat /tmp/m04-checkov-starter.log)"
echo "    ok, CKV_SECRET_2 found as expected"

echo "==> solution (with skill): fmt + validate + checkov secrets framework must PASS"
terraform -chdir=solution fmt -check -diff >/tmp/m04-fmt-sol.log 2>&1 || fail "solution not fmt-clean: $(cat /tmp/m04-fmt-sol.log)"
terraform -chdir=solution init -backend=false -input=false -no-color >/dev/null || fail "solution init"
terraform -chdir=solution validate -no-color >/tmp/m04-validate-sol.log 2>&1
grep -q "Success" /tmp/m04-validate-sol.log || fail "solution validate: $(cat /tmp/m04-validate-sol.log)"
checkov -d solution --framework secrets --compact --quiet >/tmp/m04-checkov-sol.log 2>&1 || fail "solution secrets scan: $(cat /tmp/m04-checkov-sol.log)"
echo "    ok, solution has no secrets finding"

echo "==> solution: required tags + provider pin present"
python3 - <<'PY' || fail "solution missing required tags or provider pin"
s = open("solution/main.tf").read()
p = open("solution/provider.tf").read()
assert "Environment" in s and "Owner" in s and "ManagedBy" in s, "missing required tags"
assert 'version = "~> 6.0"' in p, "missing provider pin"
PY
echo "    ok"

echo "==> starting floci ${FLOCI_VERSION}"
docker rm -f floci >/dev/null 2>&1
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "floci/floci:${FLOCI_VERSION}" >/dev/null || fail "could not start floci"
for i in $(seq 1 30); do
  curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 || fail "floci never became healthy"

echo "==> apply solution against floci"
terraform -chdir=solution apply -auto-approve -no-color >/tmp/m04-apply.log 2>&1
grep -q "Apply complete" /tmp/m04-apply.log || { tail -20 /tmp/m04-apply.log; fail "apply"; }
echo "    ok, bucket created"

echo "==> destroy"
terraform -chdir=solution destroy -auto-approve -no-color >/tmp/m04-destroy.log 2>&1
grep -q "Destroy complete" /tmp/m04-destroy.log || { tail -20 /tmp/m04-destroy.log; fail "destroy"; }
echo "    ok, bucket destroyed"

docker rm -f floci >/dev/null 2>&1
rm -rf starter/.terraform starter/.terraform.lock.hcl solution/.terraform solution/.terraform.lock.hcl solution/terraform.tfstate*

echo
echo "LAB PASSED — starter fails the secrets scan, solution is clean, applies and destroys cleanly on floci ${FLOCI_VERSION}"
