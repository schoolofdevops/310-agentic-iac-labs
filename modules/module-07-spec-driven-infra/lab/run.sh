set -uo pipefail
cd "$(dirname "$0")"
fail(){ echo "FAIL: $*" >&2; exit 1; }

echo "==> starting Floci (autoscaling, ec2, iam services)"
docker rm -f m07-floci >/dev/null 2>&1
docker run -d --name m07-floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.7.0 >/dev/null || fail "could not start floci"
for i in $(seq 1 30); do
  curl -sf http://localhost:4566/_localstack/health >/dev/null 2>&1 && break
  sleep 2
done

echo "==> spec-driven: fmt + init + validate"
terraform -chdir=spec-driven fmt -check -diff . >/tmp/m07-fmt.log 2>&1 || fail "spec-driven not fmt-clean: $(cat /tmp/m07-fmt.log)"
terraform -chdir=spec-driven init -backend=false -input=false -no-color >/dev/null || fail "spec-driven init"
terraform -chdir=spec-driven validate -no-color >/tmp/m07-validate.log 2>&1
grep -q "Success" /tmp/m07-validate.log || fail "spec-driven validate: $(cat /tmp/m07-validate.log)"

echo "==> vibe-coded: fmt + init + validate (still valid HCL, that's the point, nothing stops it)"
terraform -chdir=vibe-coded fmt -check -diff . >/tmp/m07-fmt2.log 2>&1 || fail "vibe-coded not fmt-clean: $(cat /tmp/m07-fmt2.log)"
terraform -chdir=vibe-coded init -backend=false -input=false -no-color >/dev/null || fail "vibe-coded init"
terraform -chdir=vibe-coded validate -no-color >/tmp/m07-validate2.log 2>&1
grep -q "Success" /tmp/m07-validate2.log || fail "vibe-coded validate: $(cat /tmp/m07-validate2.log)"

echo "==> the five judgment calls the ticket left silent: plan output must actually diverge"
terraform -chdir=spec-driven plan -no-color -input=false >/tmp/m07-plan-spec.log 2>&1 || fail "spec-driven plan"
terraform -chdir=vibe-coded plan -no-color -input=false >/tmp/m07-plan-vibe.log 2>&1 || fail "vibe-coded plan"
python3 -c "
import re, sys

spec = open('/tmp/m07-plan-spec.log').read()
vibe = open('/tmp/m07-plan-vibe.log').read()

def val(text, key):
    m = re.search(rf'{key}\s*=\s*(.+)', text)
    return m.group(1).strip() if m else None

checks = [
    ('health_check_grace_period', '180', '60'),
    ('min_size', '2', '2'),
    ('max_size', '4', '6'),
    ('target_value', '55', '60'),
]
for key, want_spec, want_vibe in checks:
    got_spec = val(spec, key)
    got_vibe = val(vibe, key)
    if got_spec != want_spec:
        print(f'spec-driven {key}: expected {want_spec}, got {got_spec}'); sys.exit(1)
    if got_vibe != want_vibe:
        print(f'vibe-coded {key}: expected {want_vibe}, got {got_vibe}'); sys.exit(1)

if 'termination_policies' not in spec:
    print('spec-driven should pin termination_policies explicitly'); sys.exit(1)
if 'termination_policies' in vibe:
    print('vibe-coded should leave termination_policies unset (AWS default), the whole point'); sys.exit(1)

if 'http_tokens' not in spec or 'required' not in spec:
    print('spec-driven should require IMDSv2 tokens'); sys.exit(1)
if 'http_tokens' in vibe:
    print('vibe-coded should leave metadata_options unset, IMDSv1 left reachable'); sys.exit(1)
print('    ok, all five judgment calls genuinely diverge between the two runs')
" || fail "plan-diff assertions failed"

echo "==> checkov: spec-driven passes the one check it was told to (IMDSv2), still has a real unscoped gap (tags)"
checkov -d spec-driven -o cli --compact --quiet 2>/dev/null > /tmp/m07-checkov-spec.log
grep -q "CKV_AWS_79" /tmp/m07-checkov-spec.log && grep -A1 "CKV_AWS_79" /tmp/m07-checkov-spec.log | grep -q "FAILED" && fail "spec-driven should pass CKV_AWS_79 (IMDSv2), it failed"
grep -q "CKV_AWS_153" /tmp/m07-checkov-spec.log || fail "expected CKV_AWS_153 (tags) to still fail on spec-driven, honestly, the spec never asked for it"
echo "    ok"

echo "==> checkov: vibe-coded fails exactly what FR-005 would have caught, plus real gaps on the unrequested ALB it invented"
checkov -d vibe-coded -o cli --compact --quiet 2>/dev/null > /tmp/m07-checkov-vibe.log
grep -q "CKV_AWS_79" /tmp/m07-checkov-vibe.log || fail "expected CKV_AWS_79 (IMDSv1 left on) to fail on vibe-coded"
grep -q "CKV_AWS_2" /tmp/m07-checkov-vibe.log || fail "expected an ALB/TLS finding on the ALB nobody asked for"
echo "    ok"

echo "==> spec.md carries all three real parts: requirements, constraints, success criteria"
grep -q "^### Functional Requirements" spec-driven/spec.md || fail "spec.md missing Functional Requirements"
grep -q "^### Constraints" spec-driven/spec.md || fail "spec.md missing Constraints"
grep -q "^## Success Criteria" spec-driven/spec.md || fail "spec.md missing Success Criteria"
echo "    ok"

echo "==> real apply + destroy of the spec-driven module against Floci, values checked against SC-001..SC-005"
terraform -chdir=spec-driven apply -auto-approve -input=false >/tmp/m07-apply.log 2>&1 || fail "spec-driven apply: $(tail -20 /tmp/m07-apply.log)"
terraform -chdir=spec-driven state show aws_autoscaling_group.checkout_web > /tmp/m07-state.log 2>&1
python3 -c "
import re, sys
t = open('/tmp/m07-state.log').read()
def val(key):
    m = re.search(rf'{key}\s*=\s*(.+)', t)
    return m.group(1).strip() if m else None
want = {'health_check_grace_period': '180', 'min_size': '2', 'max_size': '4', 'default_cooldown': '90'}
for k, w in want.items():
    got = val(k)
    if got != w:
        print(f'applied state {k}: expected {w}, got {got}'); sys.exit(1)
if 'OldestLaunchTemplate' not in t:
    print('applied state missing termination_policies'); sys.exit(1)
print('    ok, real applied state matches every SC value')
" || fail "applied state didn't match spec"
terraform -chdir=spec-driven destroy -auto-approve -input=false >/tmp/m07-destroy.log 2>&1 || fail "spec-driven destroy: $(tail -20 /tmp/m07-destroy.log)"
grep -q "Destroy complete" /tmp/m07-destroy.log || fail "destroy didn't complete cleanly"
echo "    ok, applied for real, values matched every success criterion, destroyed cleanly"

rm -rf spec-driven/.terraform spec-driven/.terraform.lock.hcl spec-driven/terraform.tfstate*

echo "==> Step 6: OpenTofu apply/destroy, same module"
tofu -chdir=spec-driven init -backend=false -input=false -no-color >/dev/null || fail "spec-driven tofu init"
tofu -chdir=spec-driven apply -auto-approve -input=false >/tmp/m07-tofu-apply.log 2>&1 || fail "tofu apply: $(tail -20 /tmp/m07-tofu-apply.log)"
grep -q "3 added" /tmp/m07-tofu-apply.log || fail "tofu apply: expected the same 3 resources terraform applied"
tofu -chdir=spec-driven destroy -auto-approve -input=false >/tmp/m07-tofu-destroy.log 2>&1 || fail "tofu destroy: $(tail -20 /tmp/m07-tofu-destroy.log)"
grep -q "3 destroyed" /tmp/m07-tofu-destroy.log || fail "tofu destroy didn't complete cleanly"
echo "    ok, OpenTofu applied and destroyed the identical HCL, same resource count as terraform"

rm -rf spec-driven/.terraform spec-driven/.terraform.lock.hcl spec-driven/terraform.tfstate* \
       vibe-coded/.terraform vibe-coded/.terraform.lock.hcl vibe-coded/terraform.tfstate*
docker rm -f m07-floci >/dev/null 2>&1

echo
echo "LAB PASSED, five real judgment calls genuinely diverge between the vibe-coded and"
echo "spec-driven runs, spec-driven applied for real against Floci with every value matching"
echo "its own success criteria, and checkov still found a real gap neither run's spec covered"
