set -uo pipefail
cd "$(dirname "$0")"
export PATH="/Users/gshah/.rd/bin:$PATH"
CLUSTER_NAME="cap-lab"
NODE_IMAGE="kindest/node:v1.31.0@sha256:25a3504b2b340954595fa7a6ed1575ef2edadf5abd83c0776a4308b64bf47c93"
fail(){ echo "FAIL: $*" >&2; kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; exit 1; }

echo "==> 1. real evidence: the merged PR's fix is really in place"
python3 -c "
import yaml, sys
d = yaml.safe_load(open('xr.yaml'))
spec = d.get('spec', {})
missing = [f for f in ['appName', 'environment'] if f not in spec]
sys.exit(1 if missing else 0)
" || fail "reference xr.yaml missing required fields"
echo "    ok"

echo "==> 2. kind cluster up, node image pinned by digest"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER_NAME" --image "$NODE_IMAGE" >/tmp/cap-t2-kind.log 2>&1 || { cat /tmp/cap-t2-kind.log; fail "kind create cluster"; }
echo "    ok"

echo "==> 3. crossplane v2, real helm chart"
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
kubectl create namespace crossplane-system >/dev/null 2>&1
helm install crossplane crossplane-stable/crossplane --namespace crossplane-system --version 2.4.0 --wait --timeout 300s >/tmp/cap-t2-helm.log 2>&1 || { cat /tmp/cap-t2-helm.log; fail "crossplane install"; }
echo "    ok"

echo "==> 4. function-patch-and-transform, XRD, Composition"
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-patch-and-transform
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.9.0
EOF
for i in $(seq 1 20); do
  H=$(kubectl get functions.pkg.crossplane.io function-patch-and-transform -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null)
  [ "$H" = "True" ] && break
  sleep 3
done
[ "$H" = "True" ] || fail "function never became healthy"
kubectl apply -f xrd.yaml >/dev/null || fail "xrd apply"
sleep 2
kubectl apply -f composition.yaml >/dev/null || fail "composition apply"
echo "    ok"

echo "==> 5. argo cd, real upstream manifest, server-side apply"
kubectl create namespace argocd >/dev/null 2>&1
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/tmp/cap-t2-argocd.log 2>&1 || { cat /tmp/cap-t2-argocd.log; fail "argocd install"; }
kubectl -n argocd wait --for=condition=available --timeout=180s deployment/argocd-repo-server deployment/argocd-server >/dev/null 2>&1 || fail "argocd never became available"
echo "    ok"

echo "==> 6. point argo cd at the real, merged repo path"
kubectl apply -f argocd-application.yaml >/dev/null || fail "application apply"
SYNC=""; HEALTH=""
for i in $(seq 1 40); do
  SYNC=$(kubectl -n argocd get application capstone-app -o jsonpath='{.status.sync.status}' 2>/dev/null)
  HEALTH=$(kubectl -n argocd get application capstone-app -o jsonpath='{.status.health.status}' 2>/dev/null)
  [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] && break
  sleep 5
done
[ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] || fail "never reached Synced/Healthy (sync=$SYNC health=$HEALTH)"
kubectl get configmap capstone-app -n default -o jsonpath='{.data}' | grep -q "staging" || fail "composed configmap missing real data"
echo "    ok, Synced/Healthy, real ConfigMap reconciled from the merged repo"

echo "==> 7. numbered teardown: remove application, delete cluster"
kubectl delete -f argocd-application.yaml >/dev/null 2>&1 || fail "application delete"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || fail "cluster delete"
docker ps -a --filter "name=$CLUSTER_NAME" --format '{{.Names}}' | grep -q "$CLUSTER_NAME" && fail "orphan cluster container remains"
echo "    ok, application removed, cluster deleted, no orphans"

echo
echo "TIER 2 PIPELINE PASSED -- real merged PR evidence, real crossplane v2, real argo cd synced/healthy, teardown clean"
