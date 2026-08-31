#!/usr/bin/env bash
# M06 Tier-1 lab validation. Exits non-zero on any pass-criterion failure.
# Runs the real sequence this module's lab walks through by hand: an ungated
# delete goes through, the same delete is blocked once the gate is wired in,
# a high-radius resource type is blocked, an oversized batch is blocked, and
# a safe change passes, all against a real Floci-backed aws_s3_bucket.
set -uo pipefail
cd "$(dirname "$0")"
FLOCI_VERSION="${FLOCI_VERSION:-1.7.0}"
ENDPOINT="http://localhost:4568"
TFV="-var=endpoint=${ENDPOINT}"
fail(){ echo "FAIL: $*" >&2; docker rm -f floci-m06-ci >/dev/null 2>&1; exit 1; }

cat > /tmp/m06-main.baseline <<'EOF'
resource "aws_s3_bucket" "artifacts" {
  bucket = "m06-lab-artifacts"

  tags = {
    Environment = "lab"
    Owner       = "m06-lab"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "m06-lab-logs"

  tags = {
    Environment = "lab"
    Owner       = "m06-lab"
    ManagedBy   = "terraform"
  }
}
EOF
cp /tmp/m06-main.baseline module/main.tf

echo "==> starting floci ${FLOCI_VERSION}"
docker rm -f floci-m06-ci >/dev/null 2>&1
docker run -d --name floci-m06-ci -p 4568:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "floci/floci:${FLOCI_VERSION}" >/dev/null || fail "could not start floci"
for i in $(seq 1 30); do
  curl -fsS "${ENDPOINT}/_floci/health" >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS "${ENDPOINT}/_floci/health" >/dev/null 2>&1 || fail "floci never became healthy"

echo "==> baseline: apply 2 buckets, no gate involved yet"
terraform -chdir=module init -backend=false -input=false -no-color >/dev/null || fail "init"
terraform -chdir=module apply -auto-approve -no-color $TFV >/tmp/m06-base.log 2>&1
grep -q "Apply complete" /tmp/m06-base.log || { cat /tmp/m06-base.log; fail "baseline apply"; }
echo "    ok, artifacts + logs buckets created"

echo "==> run 1: no gate, delete the logs bucket directly"
python3 - <<'PY'
h = open('module/main.tf').read()
i = h.find('resource "aws_s3_bucket" "logs"')
open('module/main.tf','w').write(h[:i].rstrip() + '\n')
PY
terraform -chdir=module apply -auto-approve -no-color $TFV >/tmp/m06-nogate-delete.log 2>&1
grep -q "1 destroyed" /tmp/m06-nogate-delete.log || { cat /tmp/m06-nogate-delete.log; fail "ungated delete should have gone through"; }
echo "    confirmed: with no gate, the delete just happens"

echo "==> restore logs bucket"
cp /tmp/m06-main.baseline module/main.tf
terraform -chdir=module apply -auto-approve -no-color $TFV >/tmp/m06-restore.log 2>&1
grep -q "Apply complete" /tmp/m06-restore.log || fail "restore"

echo "==> run 2: same delete, now through the gate, must BLOCK"
python3 - <<'PY'
h = open('module/main.tf').read()
i = h.find('resource "aws_s3_bucket" "logs"')
open('module/main.tf','w').write(h[:i].rstrip() + '\n')
PY
TF_CLI_ARGS_plan="$TFV" ./hooks/apply_with_gate.sh >/tmp/m06-gated-delete.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "gate should have blocked the delete"
grep -q "BLOCKED" /tmp/m06-gated-delete.log || fail "expected a BLOCKED message: $(cat /tmp/m06-gated-delete.log)"
terraform -chdir=module state list | grep -q "aws_s3_bucket.logs" || fail "logs bucket should still exist, gate should have stopped the apply"
echo "    ok, gate blocked the delete, bucket still exists"

echo "==> restore, then a safe additive change must PASS through the gate"
cp /tmp/m06-main.baseline module/main.tf
cat >> module/main.tf <<'EOF'

resource "aws_s3_bucket" "docs" {
  bucket = "m06-lab-docs"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}
EOF
TF_CLI_ARGS_plan="$TFV" ./hooks/apply_with_gate.sh >/tmp/m06-safe-add.log 2>&1 || { cat /tmp/m06-safe-add.log; fail "safe additive change should have passed"; }
grep -q "Apply complete" /tmp/m06-safe-add.log || fail "docs bucket should have been created"
echo "    ok, gate passed a safe change"

echo "==> high-radius resource type must BLOCK"
cat >> module/main.tf <<'EOF'

resource "aws_iam_role" "ci_deployer" {
  name = "m06-lab-ci-deployer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
EOF
TF_CLI_ARGS_plan="$TFV" ./hooks/apply_with_gate.sh >/tmp/m06-type-block.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "high-radius type should have been blocked"
grep -q "high-radius type" /tmp/m06-type-block.log || fail "expected a high-radius type block: $(cat /tmp/m06-type-block.log)"
echo "    ok, high-radius resource type blocked"

echo "==> oversized batch must BLOCK on resource count"
python3 - <<'PY'
h = open('module/main.tf').read()
i = h.find('resource "aws_iam_role"')
open('module/main.tf','w').write(h[:i].rstrip() + '\n')
PY
cat >> module/main.tf <<'EOF'

resource "aws_s3_bucket" "reports" {
  bucket = "m06-lab-reports"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}

resource "aws_s3_bucket" "backups" {
  bucket = "m06-lab-backups"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}
EOF
MAX_RESOURCES=1 TF_CLI_ARGS_plan="$TFV" ./hooks/apply_with_gate.sh >/tmp/m06-count-block.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "oversized batch should have been blocked"
grep -q "exceeds the max-resources policy" /tmp/m06-count-block.log || fail "expected a max-resources block: $(cat /tmp/m06-count-block.log)"
echo "    ok, oversized batch blocked on resource count"

echo "==> reconcile to final state and destroy everything"
cp /tmp/m06-main.baseline module/main.tf
cat >> module/main.tf <<'EOF'

resource "aws_s3_bucket" "docs" {
  bucket = "m06-lab-docs"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}
EOF
terraform -chdir=module apply -auto-approve -no-color $TFV >/tmp/m06-reconcile.log 2>&1
grep -qE "No changes|Apply complete" /tmp/m06-reconcile.log || { cat /tmp/m06-reconcile.log; fail "reconcile"; }

terraform -chdir=module destroy -auto-approve -no-color $TFV >/tmp/m06-destroy.log 2>&1
grep -q "Destroy complete" /tmp/m06-destroy.log || { tail -20 /tmp/m06-destroy.log; fail "destroy"; }
echo "    ok, all buckets destroyed"

docker rm -f floci-m06-ci >/dev/null 2>&1
rm -rf module/.terraform module/.terraform.lock.hcl module/terraform.tfstate module/terraform.tfstate.backup module/tfplan.bin module/tfplan.json
cp /tmp/m06-main.baseline module/main.tf
cat >> module/main.tf <<'EOF'

resource "aws_s3_bucket" "docs" {
  bucket = "m06-lab-docs"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}
EOF

echo
echo "LAB PASSED — ungated delete goes through, gated delete blocks, high-radius type blocks, oversized batch blocks, safe change passes, real floci ${FLOCI_VERSION} apply/destroy throughout"
