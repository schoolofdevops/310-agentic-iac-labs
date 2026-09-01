set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${1:-$HERE/work}"

if [ ! -d "$WORK_DIR" ]; then
  cp -r "$HERE/../starter" "$WORK_DIR"
fi

cd "$WORK_DIR"
terraform init -backend=false -input=false -no-color >/dev/null 2>&1
CHECKOV_OUT=$(checkov -d . --compact --quiet 2>&1)
CHECKOV_CODE=$?

if [ "$CHECKOV_CODE" -eq 0 ]; then
  echo "STOPPED: stopping condition met, checkov exits 0"
  exit 0
fi

echo "CONTINUE: stopping condition not met yet, checkov still failing"
if grep -q 'default     = "AKIA' main.tf 2>/dev/null; then
  python3 -c "
h = open('main.tf').read()
h = h.replace('  default     = \"AKIAABCDEFGHIJKLMNOP\"\n', '  sensitive   = true\n')
open('main.tf','w').write(h)
"
  echo "  (applied the real fix: pulled the hardcoded key, marked the variable sensitive)"
fi
exit 1
