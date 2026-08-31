#!/usr/bin/env bash
# Floci Tier-1 spike. Exits non-zero on any pass-criterion failure.
set -uo pipefail
FLOCI_VERSION="${FLOCI_VERSION:-1.7.0}"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> starting floci ${FLOCI_VERSION}"
docker rm -f floci >/dev/null 2>&1
# The docker socket mount is REQUIRED: RDS and EC2 spawn real backend containers.
# Without it, aws_db_instance hangs indefinitely.
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "floci/floci:${FLOCI_VERSION}" >/dev/null || fail "could not start floci"

for i in $(seq 1 30); do
  curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://localhost:4566/_floci/health >/dev/null 2>&1 || fail "floci never became healthy"

echo "==> apply"
terraform init -no-color -input=false >/dev/null || fail "init"
terraform validate -no-color >/dev/null || fail "validate"
terraform apply -auto-approve -no-color >/tmp/floci-spike-apply.log 2>&1
grep -q "Apply complete" /tmp/floci-spike-apply.log || { tail -20 /tmp/floci-spike-apply.log; fail "apply"; }
COUNT=$(terraform state list | grep -vc "^data\." )
echo "    managed resources: ${COUNT} (plus data sources)"

echo "==> criterion: RDS is a real MySQL"
MYSQLC=$(docker ps --format '{{.Names}} {{.Image}}' | awk '/mysql:8/{print $1}')
[ -n "$MYSQLC" ] || fail "no mysql backend container"
docker exec "$MYSQLC" mysql -udevopsadmin -pChangeMe12345! \
  -e "SELECT VERSION();SHOW DATABASES;" 2>/dev/null | grep -q devopsdb || fail "devopsdb not present"
echo "    ok"

echo "==> criterion: EC2 is a real Amazon Linux"
ALC=$(docker ps --format '{{.Names}} {{.Image}}' | awk '/amazonlinux/{print $1}')
[ -n "$ALC" ] || fail "no amazonlinux backend container"
docker exec "$ALC" sh -c 'command -v dnf' >/dev/null 2>&1 || fail "dnf missing in EC2 backend"
echo "    ok"

echo "==> criterion: AMI data source resolved"
terraform output -raw ami_id 2>/dev/null | grep -q '^ami-' || fail "ami data source"
echo "    ok"

echo "==> verification gates (M09 evidence)"
command -v trivy   >/dev/null && trivy config --quiet --severity HIGH,CRITICAL . 2>/dev/null | tail -5
command -v checkov >/dev/null && checkov -d . --quiet --compact --framework terraform 2>/dev/null | grep -E "Passed checks|Failed checks" | tail -2

if [ "$KEEP" = "1" ]; then
  echo "==> --keep: leaving the stack up. 'terraform destroy && docker rm -f floci' when done."
  exit 0
fi

echo "==> destroy"
terraform destroy -auto-approve -no-color >/tmp/floci-spike-destroy.log 2>&1
grep -q "Destroy complete" /tmp/floci-spike-destroy.log || { tail -20 /tmp/floci-spike-destroy.log; fail "destroy"; }
ORPHANS=$(docker ps --format '{{.Image}}' | grep -v "floci/floci" | wc -l | tr -d ' ')
[ "$ORPHANS" = "0" ] || fail "${ORPHANS} orphan container(s) left behind"
docker rm -f floci >/dev/null 2>&1
echo
echo "SPIKE PASSED — ${COUNT} managed resources applied and destroyed cleanly on floci ${FLOCI_VERSION}"
