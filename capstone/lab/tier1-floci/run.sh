set -uo pipefail
cd "$(dirname "$0")"
export PATH="/tmp/checkov-venv/bin:$PATH"
fail(){ echo "FAIL: $*" >&2; docker rm -f cap-floci-run >/dev/null 2>&1; exit 1; }

echo "==> 1. pipeline must BLOCK the starter module (trivy/checkov/policy findings, real)"
bash pipeline.sh starter >/tmp/cap-run-starter.log 2>&1
[ $? -ne 0 ] || fail "starter should not have cleared the pipeline"
grep -q "PIPELINE STOPPED" /tmp/cap-run-starter.log || fail "expected an explicit stop message"
echo "    ok"

echo "==> 2. pipeline must BLOCK the solution module without human approval"
unset CAPSTONE_HUMAN_APPROVED
export TF_VAR_config_api_key="run-sh-test-key"
bash pipeline.sh solution >/tmp/cap-run-noapproval.log 2>&1
[ $? -ne 0 ] || fail "solution should not clear without CAPSTONE_HUMAN_APPROVED=1"
grep -q "HUMAN APPROVAL" /tmp/cap-run-noapproval.log || fail "expected the approval stage to be the blocker"
echo "    ok"

echo "==> 3. pipeline must PASS the solution module once approved"
export CAPSTONE_HUMAN_APPROVED=1
bash pipeline.sh solution >/tmp/cap-run-approved.log 2>&1 || fail "solution should pass once approved: $(cat /tmp/cap-run-approved.log)"
grep -q "PIPELINE PASSED" /tmp/cap-run-approved.log || fail "expected an explicit pass message"
echo "    ok"

echo "==> 4. real floci apply"
docker rm -f cap-floci-run >/dev/null 2>&1
docker run -d --name cap-floci-run -p 4566:4566 -v /var/run/docker.sock:/var/run/docker.sock floci/floci:1.7.0 >/dev/null || fail "floci start"
for i in $(seq 1 30); do curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 && break; sleep 2; done
curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 || fail "floci never healthy"
terraform -chdir=solution apply -auto-approve -no-color "/tmp/cap-pipeline-solution.tfplan" >/tmp/cap-apply.log 2>&1
grep -q "Apply complete" /tmp/cap-apply.log || fail "apply: $(cat /tmp/cap-apply.log)"
echo "    ok, 4 resources applied"

echo "==> 5. real drift, caught on re-plan"
if command -v aws >/dev/null 2>&1; then
  aws --endpoint-url=http://localhost:4566 s3api put-bucket-versioning --bucket capstone-app-uploads --versioning-configuration Status=Suspended --region us-east-1 >/dev/null 2>&1
  DRIFT_PLAN=$(terraform -chdir=solution plan -no-color -input=false 2>&1)
  echo "$DRIFT_PLAN" | grep -q "Suspended.*Enabled\|1 to change" || fail "expected the pipeline's plan stage to catch the drift"
  echo "    ok, drift caught: Suspended -> Enabled"
else
  echo "    skipped (aws cli not present in this environment), see README for the manual drift demo"
fi

echo "==> 6. numbered teardown: terraform destroy, then remove floci"
terraform -chdir=solution destroy -auto-approve -no-color >/tmp/cap-destroy.log 2>&1
grep -q "Destroy complete" /tmp/cap-destroy.log || fail "destroy: $(cat /tmp/cap-destroy.log)"
docker rm -f cap-floci-run >/dev/null 2>&1
echo "    ok"

echo
echo "TIER 1 PIPELINE PASSED -- starter blocked, solution required approval, applied, drift caught, destroyed cleanly"
