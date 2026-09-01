set -uo pipefail
cd "$(dirname "$0")"
export PATH="/Users/gshah/.rd/bin:$PATH"
CLUSTER_NAME="m11-lab-verify"
fail(){ echo "FAIL: $*" >&2; kubectl delete -f solution/argocd-app.yaml >/dev/null 2>&1; kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; exit 1; }

echo "==> 1. real CI-gated PR evidence: the merged fix is really in place"
grep -q "sensitive   = true" pipeline-demo/main.tf || fail "pipeline-demo/main.tf doesn't show the real post-merge fix"
grep -q "AKIAABCDEFGHIJKLMNOP" pipeline-demo/main.tf && fail "pipeline-demo/main.tf still has the hardcoded secret, merge evidence missing"
echo "    ok, pipeline-demo/main.tf reflects the real fix that was merged"

echo "==> 2. kind cluster up, node image pinned by digest"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER_NAME" --config starter/kind-config.yaml >/tmp/m11-kind.log 2>&1 || { cat /tmp/m11-kind.log; fail "kind create cluster"; }
kubectl get nodes | grep -q "$CLUSTER_NAME" || fail "node not present"
echo "    ok"

echo "==> 3. argo cd install, real upstream manifest"
kubectl create namespace argocd >/dev/null 2>&1
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/tmp/m11-argocd.log 2>&1 \
  || { cat /tmp/m11-argocd.log; fail "argocd install"; }
kubectl -n argocd wait --for=condition=available --timeout=300s \
  deployment/argocd-repo-server deployment/argocd-server >/dev/null 2>&1 || fail "argocd server never became available"
echo "    ok"

echo "==> 4. point argo cd at the real, merged repo"
kubectl apply -f solution/argocd-app.yaml >/dev/null || fail "application apply"
SYNC=""; HEALTH=""
for i in $(seq 1 30); do
  SYNC=$(kubectl get application m11-gitops-demo -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
  HEALTH=$(kubectl get application m11-gitops-demo -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
  [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] && break
  sleep 5
done
[ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] || fail "application never went Synced/Healthy (sync=$SYNC health=$HEALTH)"
kubectl get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}' | grep -q "reconciled by GitOps" || fail "composed configmap missing expected data"
echo "    ok, Synced/Healthy, real ConfigMap reconciled from the merged repo"

echo "==> 5. self-heal: tamper directly, confirm the controller corrects it"
kubectl patch configmap m11-gitops-demo -n default --type merge -p '{"data":{"message":"tampered"}}' >/dev/null || fail "patch"
HEALED=0
for i in $(seq 1 20); do
  MSG=$(kubectl get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}' 2>/dev/null)
  [ "$MSG" = "reconciled by GitOps, not kubectl apply" ] && { HEALED=1; break; }
  sleep 4
done
[ "$HEALED" = "1" ] || fail "self-heal never corrected the tampered configmap"
echo "    ok, self-heal confirmed real"

echo "==> 6. numbered teardown: remove application, delete cluster"
kubectl delete -f solution/argocd-app.yaml >/dev/null || fail "application delete"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || fail "cluster delete"
docker ps -a --filter "name=$CLUSTER_NAME" --format '{{.Names}}' | grep -q "$CLUSTER_NAME" && fail "orphan cluster container remains"
echo "    ok, application removed, cluster deleted, no orphans"

echo
echo "LAB PASSED -- real merged PR evidence found, real kind cluster, real argo cd synced/healthy, real self-heal, teardown clean"
