#!/usr/bin/env bash
# Step (c): the explicit human gate. Nothing upstream of this script can
# apply anything. A plan file with no matching .approved marker next to it
# is not approved, no matter how safe it looks.
set -uo pipefail
PLAN="${1:?usage: approve.sh plans/<file>.md}"
cd "$(dirname "$0")/.."

[ -f "$PLAN" ] || { echo "REFUSED: no such plan file: $PLAN" >&2; exit 1; }

APPROVER="${APPROVER:-$(whoami)}"
{
  echo "approved-by: ${APPROVER}"
  echo "approved-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "approved-plan: ${PLAN}"
} > "${PLAN}.approved"

echo "APPROVED: ${PLAN} (by ${APPROVER})"
