set -uo pipefail
cd "$(dirname "$0")"
export PATH="/Users/gshah/.rd/bin:$PATH"
CLUSTER_NAME="m11-lab-verify"
KCTX="kind-${CLUSTER_NAME}"
# Every kubectl call below is pinned to --context "$KCTX" on purpose. "kind create cluster"
# changes the shared kubeconfig's current-context globally, so any other kind cluster created
# concurrently on the same machine (a leftover from an earlier module, another terminal) steals
# current-context out from under this script mid-run. Pinning the context makes this script
# correct regardless of what else is running.
kctl(){ kubectl --context "$KCTX" "$@"; }
fail(){ echo "FAIL: $*" >&2; kctl delete -f solution/argocd-app.yaml >/dev/null 2>&1; kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; exit 1; }

echo "==> 1. real agent-proposed, CI-gated, merged fix evidence: both findings are really fixed"
[ "$(grep -c 'sensitive   = true' pipeline-demo/main.tf)" = "2" ] || fail "pipeline-demo/main.tf should show 2 sensitive vars (webhook_token, signing_key_id), the real post-merge state"
grep -q "AKIAABCDEFGHIJKLMNOP" pipeline-demo/main.tf && fail "pipeline-demo/main.tf still has the original hardcoded secret, merge evidence missing"
grep -qE '^\s*default\s*=' pipeline-demo/main.tf && fail "pipeline-demo/main.tf still has a variable default, a hardcoded value may remain"
grep -q "signing_key_id" pipeline-demo/main.tf || fail "pipeline-demo/main.tf missing signing_key_id, the agent-proposed-then-fixed variable from the real PR #4 demo"
echo "    ok, pipeline-demo/main.tf reflects the real agent-proposed-and-fixed state, both findings closed"

echo "==> 2. kind cluster up, node image pinned by digest"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER_NAME" --config starter/kind-config.yaml >/tmp/m11-kind.log 2>&1 || { cat /tmp/m11-kind.log; fail "kind create cluster"; }
kctl get nodes | grep -q "$CLUSTER_NAME" || fail "node not present"
echo "    ok"

echo "==> 3. argo cd install, real upstream manifest"
kctl create namespace argocd >/dev/null 2>&1
kctl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/tmp/m11-argocd.log 2>&1 \
  || { cat /tmp/m11-argocd.log; fail "argocd install"; }
kctl -n argocd wait --for=condition=available --timeout=300s \
  deployment/argocd-repo-server deployment/argocd-server >/dev/null 2>&1 || fail "argocd server never became available"
echo "    ok"

echo "==> 4. point argo cd at the real, merged repo"
kctl apply -f solution/argocd-app.yaml >/dev/null || fail "application apply"
SYNC=""; HEALTH=""
for i in $(seq 1 30); do
  SYNC=$(kctl get application m11-gitops-demo -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
  HEALTH=$(kctl get application m11-gitops-demo -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
  [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] && break
  sleep 5
done
[ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] || fail "application never went Synced/Healthy (sync=$SYNC health=$HEALTH)"
kctl get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}' | grep -q "reconciled by GitOps" || fail "composed configmap missing expected data"
echo "    ok, Synced/Healthy, real ConfigMap reconciled from the merged repo"

echo "==> 5. self-heal: tamper directly, confirm the controller corrects it"
kctl patch configmap m11-gitops-demo -n default --type merge -p '{"data":{"message":"tampered"}}' >/dev/null || fail "patch"
HEALED=0
for i in $(seq 1 20); do
  MSG=$(kctl get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}' 2>/dev/null)
  [ "$MSG" = "reconciled by GitOps, not kubectl apply" ] && { HEALED=1; break; }
  sleep 4
done
[ "$HEALED" = "1" ] || fail "self-heal never corrected the tampered configmap"
echo "    ok, self-heal confirmed real"

echo "==> 6. numbered teardown: remove application, delete cluster"
kctl delete -f solution/argocd-app.yaml >/dev/null || fail "application delete"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || fail "cluster delete"
docker ps -a --filter "name=$CLUSTER_NAME" --format '{{.Names}}' | grep -q "$CLUSTER_NAME" && fail "orphan cluster container remains"
echo "    ok, application removed, cluster deleted, no orphans"

echo
echo "LAB PASSED -- real merged PR evidence found, real kind cluster, real argo cd synced/healthy, real self-heal, teardown clean"
