#!/usr/bin/env bash
# verify_claim.sh -- blocks a completion claim ("checkov passes", "tests pass",
# "it's clean", "this works") unless real command evidence backs it up in the
# same transcript. Takes one argument: a plain-text transcript file (what the
# agent actually said, plus any tool output it actually produced).
#
# Real evidence, for this lab, means a line that looks like real checkov
# output: "Passed checks:" / "Failed checks:" counts, or a real non-zero/zero
# exit code line. A claim with no such line nearby is unbacked and gets
# blocked, same as this course's own verification discipline.
set -uo pipefail

FILE="${1:-}"
[ -f "$FILE" ] || { echo "BLOCK: no transcript file given" >&2; exit 1; }

CLAIM_RE='(checkov (passes|is clean|clean)|tests? pass(es)?|it works|this works|is clean now|no (more )?findings)'
EVIDENCE_RE='(Passed checks: [0-9]+, Failed checks: [0-9]+|Check: CKV|exit code:? *0|\$ checkov)'

if ! grep -Eiq "$CLAIM_RE" "$FILE"; then
  echo "PASS: no completion claim found, nothing to verify"
  exit 0
fi

if grep -Eiq "$EVIDENCE_RE" "$FILE"; then
  echo "PASS: completion claim found, and real command evidence backs it up"
  exit 0
fi

echo "BLOCK: completion claim found with no real command evidence in the transcript" >&2
exit 1
