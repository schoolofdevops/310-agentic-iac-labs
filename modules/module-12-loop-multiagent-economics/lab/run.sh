set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; rm -rf solution/work; exit 1; }

rm -rf solution/work

echo "==> 1. trigger config: real, valid cron"
python3 -c "
import yaml
d = yaml.safe_load(open('solution/trigger-workflow.example.yml'))
cron = d[True]['schedule'][0]['cron']
parts = cron.split()
assert len(parts) == 5, 'not a real 5-field cron expression'
assert 'workflow_dispatch' in d[True]
print('    ok, cron:', cron)
" || fail "trigger config invalid"

echo "==> 2. run 1: stopping condition not yet met, must CONTINUE"
OUT1=$(bash solution/loop.sh solution/work 2>&1)
echo "$OUT1" | grep -q "^CONTINUE:" || fail "run 1 should have printed CONTINUE, got: $OUT1"
echo "    ok"

echo "==> 3. run 2: same work dir, real fix now applied, must STOP"
OUT2=$(bash solution/loop.sh solution/work 2>&1)
echo "$OUT2" | grep -q "^STOPPED:" || fail "run 2 should have printed STOPPED, got: $OUT2"
echo "    ok"

echo "==> 4. run 3: already stopped, re-trigger must be idempotent, still STOPPED"
OUT3=$(bash solution/loop.sh solution/work 2>&1)
echo "$OUT3" | grep -q "^STOPPED:" || fail "run 3 should still be STOPPED, got: $OUT3"
echo "    ok"

rm -rf solution/work

echo "==> Step 5: FinOps gate"
python3 finops/gate.py finops/plan-over-budget.json && fail "gate should have rejected plan-over-budget.json"
python3 finops/gate.py finops/plan-in-budget.json || fail "gate should have accepted plan-in-budget.json"
echo "    ok, FinOps gate rejects plan-over-budget.json and accepts plan-in-budget.json"

echo
echo "LAB PASSED -- real stopping-condition loop: run 1 continues and applies the real fix, run 2 stops, run 3 is idempotent, FinOps gate rejects and accepts correctly"
