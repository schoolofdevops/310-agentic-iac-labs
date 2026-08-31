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

echo
echo "LAB PASSED — terraform MCP image real and responsive, config valid, captured evidence shows a real stale-vs-live gap and a real opened-then-closed PR"
