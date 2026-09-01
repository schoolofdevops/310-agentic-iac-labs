#!/usr/bin/env bash
# Step (d): the second real invocation, the only one allowed to touch files.
# Refuses outright if plans/<file>.md.approved doesn't exist. Once approved,
# a fresh Claude Code session edits module/main.tf to match the approved
# plan, nothing else, then the existing mechanical gate (blast_radius_gate.sh)
# still runs before terraform ever applies. Two independent guardrails,
# stacked: one about who said yes, one about what the plan actually contains.
set -uo pipefail
PLAN="${1:?usage: apply_with_approval.sh plans/<file>.md}"
cd "$(dirname "$0")/.."

if [ ! -f "${PLAN}.approved" ]; then
  echo "REFUSED: ${PLAN} has not been approved. Run harness/approve.sh first." >&2
  exit 1
fi
echo "==> approval found: $(tr '\n' ' ' < "${PLAN}.approved")"

claude -p "Read the approved plan at ${PLAN}. Apply exactly what it proposes by editing module/main.tf. Do not deviate from the plan, do not add anything it doesn't describe." \
  --permission-mode acceptEdits --allowedTools "Read,Edit"

echo "==> agent edited module/main.tf per the approved plan, now running the mechanical gate before any real apply"
./hooks/apply_with_gate.sh
