set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> terraform MCP server image: real pull + real --help response"
docker pull hashicorp/terraform-mcp-server:latest >/tmp/m05-pull.log 2>&1 || fail "docker pull: $(cat /tmp/m05-pull.log)"
docker run --rm hashicorp/terraform-mcp-server:latest --help >/tmp/m05-help.log 2>&1
grep -q "terraform-mcp-server" /tmp/m05-help.log || fail "image did not respond to --help"
echo "    ok"

echo "==> mcp-config files are valid JSON and shaped correctly"
python3 -c "
import json
t = json.load(open('mcp-config/terraform.mcp.json'))
assert t['mcpServers']['terraform']['command'] == 'docker'
g = json.load(open('mcp-config/github.mcp.json'))
assert g['mcpServers']['github']['url'].startswith('https://api.githubcopilot.com')
print('    ok')
" || fail "mcp-config JSON"

echo "==> evidence: the stale answer is really low-confidence"
grep -qi "guess\|not certain\|low" evidence/stale-answer.txt || fail "stale-answer.txt doesn't read like a hedge"
echo "    ok"

echo "==> evidence: the MCP answer really cites a tool"
grep -q "mcp__terraform" evidence/mcp-answer.txt || fail "mcp-answer.txt doesn't cite an MCP tool call"
echo "    ok"

echo "==> evidence: the two answers actually disagree on the version number"
python3 -c "
import re
stale = open('evidence/stale-answer.txt').read()
mcp = open('evidence/mcp-answer.txt').read()
sv = re.search(r'v?~?(\d+\.\d+\.\d+)', stale).group(1)
mv = re.search(r'\*\*(\d+\.\d+\.\d+)\*\*', mcp).group(1)
assert sv != mv, f'expected these to differ, got {sv} == {mv}'
print(f'    ok, stale said {sv}, mcp said {mv}')
" || fail "version comparison"

echo "==> evidence: the PR really opened, then really closed without merging"
python3 -c "
import json
opened = json.load(open('evidence/pr-opened.json'))
closed = json.load(open('evidence/pr-closed.json'))
assert opened['state'] == 'open', opened.get('state')
assert closed['state'] == 'closed', closed.get('state')
assert closed['merged'] is False, closed.get('merged')
assert opened['number'] == closed['number']
print(f\"    ok, PR #{opened['number']} opened then closed, never merged\")
" || fail "PR evidence"

echo "==> evidence: Terraform MCP was really asked about aws_db_parameter_group"
grep -qi "family" evidence/param-group-mcp-answer.txt || fail "param-group-mcp-answer.txt doesn't mention the family argument"
grep -qi "mysql8" evidence/param-group-mcp-answer.txt || fail "param-group-mcp-answer.txt doesn't land on mysql8.0"
echo "    ok"

echo "==> evidence: aws-iac-mcp-server was really attempted, and honestly failed to start"
grep -q "ModuleNotFoundError\|TypeError" evidence/aws-iac-mcp-server-attempt.txt || fail "attempt evidence doesn't show a real crash"
echo "    ok, this module doesn't paper over an immature dependency, it shows you the real failure"

echo "==> checkov: a seeded storage_encrypted=false must fail CKV_AWS_16, the fixed module must pass"
rm -rf /tmp/m05-checkov-scratch
cp -r module /tmp/m05-checkov-scratch
sed -i.bak 's/storage_encrypted       = true/storage_encrypted       = false/' /tmp/m05-checkov-scratch/db.tf
grep -q "storage_encrypted       = false" /tmp/m05-checkov-scratch/db.tf || fail "seed did not take, db.tf still has storage_encrypted = true"
checkov -d /tmp/m05-checkov-scratch --framework terraform --check CKV_AWS_16 --compact --quiet >/tmp/m05-checkov-seeded.log 2>&1
CODE=$?
[ "$CODE" -ne 0 ] || fail "seeded module unexpectedly passed checkov, CKV_AWS_16 should have caught storage_encrypted=false"
grep -q "CKV_AWS_16" /tmp/m05-checkov-seeded.log || fail "expected CKV_AWS_16 finding, got: $(cat /tmp/m05-checkov-seeded.log)"
echo "    ok, CKV_AWS_16 found as expected on the seeded module"

checkov -d module --framework terraform --check CKV_AWS_16 --compact --quiet >/tmp/m05-checkov-fixed.log 2>&1 || fail "shipped module: checkov CKV_AWS_16: $(cat /tmp/m05-checkov-fixed.log)"
grep -q "Passed checks: 1, Failed checks: 0" /tmp/m05-checkov-fixed.log || fail "shipped module did not pass CKV_AWS_16 cleanly: $(cat /tmp/m05-checkov-fixed.log)"
echo "    ok, shipped module (storage_encrypted = true) passes CKV_AWS_16"
rm -rf /tmp/m05-checkov-scratch

echo "==> the RDS-with-parameter-group module: real Floci apply, real destroy"
if ! curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1; then
  fail "Floci isn't running on :4566, start it first: docker compose -f ../../../labs/shared/docker-compose.floci.yml up -d"
fi
cd module
terraform init -input=false -upgrade=false >/tmp/m05-init.log 2>&1 || fail "terraform init: $(tail -20 /tmp/m05-init.log)"
terraform apply -auto-approve -input=false >/tmp/m05-apply.log 2>&1 || fail "terraform apply: $(tail -30 /tmp/m05-apply.log)"
grep -q "Apply complete" /tmp/m05-apply.log || fail "apply did not report complete"
echo "    ok, applied"

terraform show -json > /tmp/m05-run-show.json
python3 -c "
import json
d = json.load(open('/tmp/m05-run-show.json'))
res = {r['address']: r for r in d['values']['root_module']['resources']}
pg_name = res['aws_db_parameter_group.app']['values']['name']
db_pg   = res['aws_db_instance.app']['values']['parameter_group_name']
assert db_pg == pg_name, f'db instance parameter_group_name={db_pg} does not match the real parameter group {pg_name}'
params = res['aws_db_parameter_group.app']['values']['parameter']
names = {p['name'] for p in params}
assert 'slow_query_log' in names, f'expected a real non-default parameter, got {names}'
print(f'    ok, aws_db_instance.app really wired to parameter group {pg_name} ({sorted(names)})')
" || fail "parameter group wiring check"

terraform destroy -auto-approve -input=false >/tmp/m05-destroy.log 2>&1 || fail "terraform destroy: $(tail -30 /tmp/m05-destroy.log)"
grep -q "Destroy complete" /tmp/m05-destroy.log || fail "destroy did not report complete"
echo "    ok, destroyed"
cd ..

echo
echo "LAB PASSED: terraform MCP image real and responsive, config valid, captured evidence shows a real stale-vs-live gap, a real aws_db_parameter_group lookup, a real (and honestly failed) aws-iac-mcp-server attempt, an opened-then-closed PR, a seeded-then-fixed CKV_AWS_16 encryption gap, and a real applied-then-destroyed RDS-with-parameter-group module"
