#!/usr/bin/env bash
# Step (a) of the plan-review-approve-apply harness: ask a real Claude Code
# session to propose an infrastructure change in --permission-mode plan.
# Plan mode cannot write files, so nothing changes yet. It saves a real plan
# document under ~/.claude/plans/, and this script copies that same file into
# plans/, the reviewable, project-local location the next two steps read from.
set -uo pipefail
ASK="${1:?usage: propose.sh \"<intent>\"}"
cd "$(dirname "$0")/.."

BEFORE=$(date +%s)
claude -p "${ASK} Propose the exact HCL to add to module/main.tf. Do not write any files, this is a proposal only." \
  --permission-mode plan

LATEST=""
for f in $(ls -t "$HOME/.claude/plans/"*.md 2>/dev/null); do
  MTIME=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
  if [ "$MTIME" -ge "$BEFORE" ]; then
    LATEST="$f"
    break
  fi
done

if [ -z "$LATEST" ]; then
  echo "REFUSED: no plan file appeared under ~/.claude/plans/ after this invocation." >&2
  echo "Nothing to review, nothing to approve, nothing gets applied." >&2
  exit 1
fi

SLUG=$(basename "$LATEST")
cp "$LATEST" "plans/${SLUG}"
echo
echo "PLAN_SAVED: plans/${SLUG}"
