#!/usr/bin/env bash
# M04 Tier-1 lab validation. Exits non-zero on any pass-criterion failure.
set -uo pipefail
cd "$(dirname "$0")"
FLOCI_VERSION="${FLOCI_VERSION:-1.7.0}"
export TF_VAR_artifact_uploader_key="AKIAFAKELABKEY000111"
# Share one provider download across every terraform init in this script (starter,
# solution, and Part II's three VPC environments all pin the same aws ~> 6.0 provider) so
# re-runs don't re-download it four more times over the network.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
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
echo "==> Part II: vpc/envs/{dev,staging,prod} must all validate clean"
for env in dev staging prod; do
  terraform -chdir="vpc/envs/${env}" fmt -check -diff >/tmp/m04-vpc-fmt-${env}.log 2>&1 || fail "vpc/${env} not fmt-clean: $(cat /tmp/m04-vpc-fmt-${env}.log)"
  terraform -chdir="vpc/envs/${env}" init -backend=false -input=false -no-color >/dev/null || fail "vpc/${env} init"
  terraform -chdir="vpc/envs/${env}" validate -no-color >/tmp/m04-vpc-validate-${env}.log 2>&1
  grep -q "Success" /tmp/m04-vpc-validate-${env}.log || fail "vpc/${env} validate: $(cat /tmp/m04-vpc-validate-${env}.log)"
done
echo "    ok, dev/staging/prod all validate clean"

echo "==> Part II: overlap checker must PASS on the real, non-overlapping environments"
python3 .claude/skills/vpc-environment-scaffold/scripts/check_cidr_overlap.py vpc/envs >/tmp/m04-overlap-clean.log 2>&1 || fail "overlap checker unexpectedly failed: $(cat /tmp/m04-overlap-clean.log)"
grep -q "no CIDR overlap" /tmp/m04-overlap-clean.log || fail "overlap checker didn't report clean: $(cat /tmp/m04-overlap-clean.log)"
echo "    ok, no overlap across dev/staging/prod"

echo "==> Part II: overlap checker must CATCH a real seeded collision"
rm -rf /tmp/m04-overlap-test
mkdir -p /tmp/m04-overlap-test/dev /tmp/m04-overlap-test/staging /tmp/m04-overlap-test/prod
cp vpc/envs/dev/terraform.tfvars /tmp/m04-overlap-test/dev/
cp vpc/envs/staging/terraform.tfvars /tmp/m04-overlap-test/staging/
cp vpc/envs/prod/terraform.tfvars /tmp/m04-overlap-test/prod/
python3 - <<'PY'
p = "/tmp/m04-overlap-test/staging/terraform.tfvars"
text = open(p).read().replace("10.11.0.0/16", "10.10.128.0/17")
open(p, "w").write(text)
PY
python3 .claude/skills/vpc-environment-scaffold/scripts/check_cidr_overlap.py /tmp/m04-overlap-test >/tmp/m04-overlap-seeded.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "overlap checker missed a real seeded collision"
grep -q "CIDR OVERLAP DETECTED" /tmp/m04-overlap-seeded.log || fail "expected overlap message, got: $(cat /tmp/m04-overlap-seeded.log)"
rm -rf /tmp/m04-overlap-test
echo "    ok, seeded dev/staging overlap caught, real exit code ${CODE}"

echo "==> starting floci ${FLOCI_VERSION} for Part II"
docker rm -f floci >/dev/null 2>&1
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "floci/floci:${FLOCI_VERSION}" >/dev/null || fail "could not start floci"
for i in $(seq 1 30); do
  curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 || fail "floci never became healthy"

echo "==> apply vpc/envs/dev against floci"
export TF_VAR_endpoint="http://localhost:4566"
terraform -chdir=vpc/envs/dev apply -auto-approve -no-color >/tmp/m04-vpc-apply.log 2>&1
grep -q "Apply complete" /tmp/m04-vpc-apply.log || { tail -20 /tmp/m04-vpc-apply.log; fail "vpc dev apply"; }
grep -q "12 added" /tmp/m04-vpc-apply.log || fail "vpc dev apply didn't create the expected 12 resources"
echo "    ok, dev VPC (vpc + igw + nat + eip + 2 subnets + 2 route tables + 2 assocs + 2 routes) created"

echo "==> destroy vpc/envs/dev"
terraform -chdir=vpc/envs/dev destroy -auto-approve -no-color >/tmp/m04-vpc-destroy.log 2>&1
grep -q "Destroy complete" /tmp/m04-vpc-destroy.log || { tail -20 /tmp/m04-vpc-destroy.log; fail "vpc dev destroy"; }
echo "    ok, dev VPC destroyed"

docker rm -f floci >/dev/null 2>&1
for env in dev staging prod; do
  rm -rf "vpc/envs/${env}/.terraform" "vpc/envs/${env}/.terraform.lock.hcl" "vpc/envs/${env}"/terraform.tfstate*
done

echo
echo "==> Stage 3: skill audit"
grep -c "credentials\|id_rsa" .claude/skills/terraform-formatter-untrusted/SKILL.md > /tmp/m04-audit-count.txt
[ "$(cat /tmp/m04-audit-count.txt)" = "0" ] || fail "terraform-formatter-untrusted/SKILL.md still grants credential access"
echo "    ok, terraform-formatter-untrusted/SKILL.md grants no credential access"

echo
echo "LAB PASSED, Part I: starter fails the secrets scan, solution is clean, applies and destroys cleanly on floci ${FLOCI_VERSION}."
echo "             Part II: dev/staging/prod all validate, the skill's bundled overlap checker passes clean and catches a real"
echo "             seeded collision, and dev's 12-resource VPC applies and destroys cleanly on floci ${FLOCI_VERSION}."
echo "             Stage 3: terraform-formatter-untrusted/SKILL.md carries no credential read."
