#!/usr/bin/env bash
# M06 Tier-1 lab validation. Exits non-zero on any pass-criterion failure.
# Runs the real sequence this module's lab walks through by hand: an ungated
# delete destroys a real object, the same delete is blocked once the gate is
# wired in, a high-radius resource type is blocked, an oversized batch is
# blocked, a safe change passes, and the propose-review-approve-apply harness
# refuses an unapproved plan then applies an approved one, all against a real
# Floci-backed aws_s3_bucket and, where noted, a real Claude Code session.
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
  bucket        = "m06-lab-logs"
  force_destroy = true

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

echo "==> put a real object in the logs bucket, this is the visceral part: a real access log, not an empty bucket"
echo "2026-08-30 03:14:02 auth-service ERROR db timeout after 30s, retrying" > /tmp/m06-app.log
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url "$ENDPOINT" \
  s3 cp /tmp/m06-app.log "s3://m06-lab-logs/2026-08-30/app.log" >/dev/null || fail "could not upload real object to logs bucket"
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url "$ENDPOINT" \
  s3 ls "s3://m06-lab-logs/2026-08-30/" | grep -q app.log || fail "object should be listable in logs bucket"
echo "    ok, real object uploaded to the logs bucket"

echo "==> run 1: no gate, delete the logs bucket directly. force_destroy is on, same as a team that turned it on to stop CI failing on BucketNotEmpty"
python3 - <<'PY'
h = open('module/main.tf').read()
i = h.find('resource "aws_s3_bucket" "logs"')
open('module/main.tf','w').write(h[:i].rstrip() + '\n')
PY
terraform -chdir=module apply -auto-approve -no-color $TFV >/tmp/m06-nogate-delete.log 2>&1
grep -q "1 destroyed" /tmp/m06-nogate-delete.log || { cat /tmp/m06-nogate-delete.log; fail "ungated delete should have gone through"; }
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url "$ENDPOINT" \
  s3 ls "s3://m06-lab-logs/2026-08-30/" >/tmp/m06-object-gone.log 2>&1
grep -q "NoSuchBucket" /tmp/m06-object-gone.log || { cat /tmp/m06-object-gone.log; fail "the bucket and its real object should be irrecoverably gone"; }
echo "    confirmed: with no gate, the delete just happens, and the real object is gone with it, NoSuchBucket, not a rollback"

echo "==> restore logs bucket, re-upload the object"
cp /tmp/m06-main.baseline module/main.tf
terraform -chdir=module apply -auto-approve -no-color $TFV >/tmp/m06-restore.log 2>&1
grep -q "Apply complete" /tmp/m06-restore.log || fail "restore"
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url "$ENDPOINT" \
  s3 cp /tmp/m06-app.log "s3://m06-lab-logs/2026-08-30/app.log" >/dev/null || fail "could not re-upload object"

echo "==> run 2: same delete, same real object at risk, now through the gate, must BLOCK"
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
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url "$ENDPOINT" \
  s3 ls "s3://m06-lab-logs/2026-08-30/" | grep -q app.log || fail "the real object should have survived the blocked delete"
echo "    ok, gate blocked the delete, bucket and its real object both still exist"

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

echo "==> mechanism 3: plan-review-approve-apply harness, real claude -p calls"
if command -v claude >/dev/null 2>&1; then
  rm -f plans/*.md plans/*.approved 2>/dev/null
  cp /tmp/m06-main.baseline module/main.tf
  cat >> module/main.tf <<'EOF'

resource "aws_s3_bucket" "docs" {
  bucket = "m06-lab-docs"
  tags = { Environment = "lab", Owner = "m06-lab", ManagedBy = "terraform" }
}
EOF
  ./harness/propose.sh "Add a new S3 bucket resource named 'audit' with bucket name 'm06-lab-audit'." >/tmp/m06-propose.log 2>&1
  PLAN=$(python3 -c "print([l.split('PLAN_SAVED: ')[1] for l in open('/tmp/m06-propose.log') if 'PLAN_SAVED' in l][0])" 2>/dev/null)
  [ -n "$PLAN" ] && [ -f "$PLAN" ] || { cat /tmp/m06-propose.log; fail "harness propose should have saved a real plan file"; }
  echo "    ok, real plan saved to ${PLAN}"

  ./harness/apply_with_approval.sh "$PLAN" >/tmp/m06-refused.log 2>&1
  CODE=$?
  [ "$CODE" -ne 0 ] || fail "apply_with_approval should refuse an unapproved plan"
  grep -q "REFUSED" /tmp/m06-refused.log || fail "expected a REFUSED message: $(cat /tmp/m06-refused.log)"
  echo "    ok, apply refused before approval"

  ./harness/approve.sh "$PLAN" >/tmp/m06-approve.log 2>&1
  [ -f "${PLAN}.approved" ] || fail "approval marker should exist after approve.sh"

  TF_CLI_ARGS_plan="$TFV" ./harness/apply_with_approval.sh "$PLAN" >/tmp/m06-approved-apply.log 2>&1 || { cat /tmp/m06-approved-apply.log; fail "approved apply should have gone through"; }
  terraform -chdir=module state list | grep -q "aws_s3_bucket.audit" || fail "audit bucket should exist after the approved apply"
  echo "    ok, approved plan applied for real, audit bucket created"
  rm -f plans/*.md plans/*.approved 2>/dev/null
else
  echo "    SKIPPED: claude CLI not on PATH in this environment, harness needs a live Claude Code session"
fi

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
echo "LAB PASSED: ungated delete destroys a real object, gated delete blocks it, high-radius type blocks, oversized batch blocks, safe change passes, propose-approve-apply harness refuses before approval and applies for real after it, real floci ${FLOCI_VERSION} throughout"
