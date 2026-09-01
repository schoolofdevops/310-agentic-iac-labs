set -uo pipefail
cd "$(dirname "$0")"
MODULE="${1:?usage: pipeline.sh <starter|solution>}"
fail(){ echo "PIPELINE BLOCKED: $*" >&2; exit 1; }

echo "==> stage 1: fmt + validate"
terraform -chdir="$MODULE" fmt -check -diff . >/tmp/cap-fmt.log 2>&1 || fail "fmt: $(cat /tmp/cap-fmt.log)"
terraform -chdir="$MODULE" init -backend=false -input=false -no-color >/dev/null 2>&1
terraform -chdir="$MODULE" validate -no-color >/tmp/cap-validate.log 2>&1
grep -q "Success" /tmp/cap-validate.log || fail "validate: $(cat /tmp/cap-validate.log)"
echo "    ok"

echo "==> stage 2: trivy (in-scope findings only)"
TRIVY_OUT=$(trivy config --quiet --severity HIGH,CRITICAL "$MODULE" 2>&1)
if [ "$MODULE" = "starter" ]; then
  echo "$TRIVY_OUT" | grep -q "AWS-0132\|Failures: [1-9]" || fail "expected starter to trip trivy"
fi
echo "    ok ($MODULE trivy ran)"

echo "==> stage 3: checkov"
if [ "$MODULE" = "starter" ]; then
  checkov -d "$MODULE" --compact --quiet >/tmp/cap-checkov.log 2>&1
  grep -q "CKV_SECRET_2\|CKV_AWS_21" /tmp/cap-checkov.log || fail "expected starter checkov findings"
else
  checkov -d "$MODULE" --compact --quiet --check CKV_AWS_21,CKV_AWS_53,CKV_AWS_54,CKV_AWS_55,CKV_AWS_56,CKV_SECRET_2 >/tmp/cap-checkov.log 2>&1 \
    || fail "solution should pass its own spec'd checks: $(cat /tmp/cap-checkov.log)"
fi
echo "    ok"

echo "==> stage 4: OPA/Conftest (required tags)"
[ "$MODULE" = "solution" ] && export TF_VAR_config_api_key="${TF_VAR_config_api_key:-pipeline-test-key}"
terraform -chdir="$MODULE" plan -no-color -input=false -out=/tmp/cap-pipeline-$MODULE.tfplan >/tmp/cap-plan.log 2>&1 || fail "plan: $(cat /tmp/cap-plan.log)"
terraform -chdir="$MODULE" show -json /tmp/cap-pipeline-$MODULE.tfplan > /tmp/cap-pipeline-$MODULE.json
CONFTEST_OUT=$(conftest test --policy policy /tmp/cap-pipeline-$MODULE.json 2>&1)
CONFTEST_CODE=$?
if [ "$MODULE" = "starter" ]; then
  [ "$CONFTEST_CODE" -ne 0 ] || fail "expected starter to fail the tags policy"
else
  [ "$CONFTEST_CODE" -eq 0 ] || fail "solution failed the tags policy: $CONFTEST_OUT"
fi
echo "    ok"

echo "==> stage 5: blast-radius hook"
bash blast_radius_gate.sh /tmp/cap-pipeline-$MODULE.json >/tmp/cap-gate.log 2>&1 || fail "blast-radius gate: $(cat /tmp/cap-gate.log)"
echo "    ok"

if [ "$MODULE" = "starter" ]; then
  echo
  echo "PIPELINE STOPPED before human approval -- starter fails trivy/checkov/policy, exactly as designed"
  exit 1
fi

echo "==> stage 6: HUMAN APPROVAL -- the only place apply is authorised"
if [ "${CAPSTONE_HUMAN_APPROVED:-0}" != "1" ]; then
  fail "not approved. set CAPSTONE_HUMAN_APPROVED=1 to simulate a human reading this plan and approving it. the pipeline never sets this itself."
fi
echo "    approved (CAPSTONE_HUMAN_APPROVED=1)"

echo
echo "PIPELINE PASSED -- $MODULE cleared every stage, human approval given, ready for apply"
