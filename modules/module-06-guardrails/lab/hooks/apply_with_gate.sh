#!/usr/bin/env bash
# Wraps `terraform apply` with the blast-radius gate. This is the enforced half:
# the gate runs every time, whether or not anything asked for it.
set -uo pipefail
cd "$(dirname "$0")/../module"

terraform plan -no-color -input=false -out=tfplan.bin >/tmp/m06-plan.log 2>&1 || { cat /tmp/m06-plan.log; exit 1; }
terraform show -json tfplan.bin > tfplan.json

if ! ../hooks/blast_radius_gate.sh tfplan.json; then
  echo "apply refused: gate blocked this plan." >&2
  rm -f tfplan.bin tfplan.json
  exit 1
fi

terraform apply -no-color -input=false -auto-approve tfplan.bin
rm -f tfplan.bin tfplan.json
