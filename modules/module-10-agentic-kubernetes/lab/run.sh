set -uo pipefail
cd "$(dirname "$0")"
export PATH="/Users/gshah/.rd/bin:$PATH"
fail(){ echo "FAIL: $*" >&2; kind delete cluster --name m10-lab >/dev/null 2>&1; exit 1; }

CLUSTER_NAME="m10-lab"
NODE_IMAGE="kindest/node:v1.31.0@sha256:25a3504b2b340954595fa7a6ed1575ef2edadf5abd83c0776a4308b64bf47c93"

echo "==> 1. kind cluster up, node image pinned by digest"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --config starter/kind-config.yaml >/tmp/m10-kind.log 2>&1 || { cat /tmp/m10-kind.log; fail "kind create cluster"; }
kubectl get nodes | grep -q "$CLUSTER_NAME" || fail "node not present"
echo "    ok"

echo "==> 2. crossplane v2 via real helm chart"
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
kubectl create namespace crossplane-system >/dev/null 2>&1
helm install crossplane crossplane-stable/crossplane --namespace crossplane-system --version 2.4.0 --wait --timeout 300s >/tmp/m10-helm.log 2>&1 || { cat /tmp/m10-helm.log; fail "crossplane install"; }
CP_VERSION=$(helm list -n crossplane-system -o json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['app_version'])")
[[ "$CP_VERSION" == 2.* ]] || fail "expected crossplane v2, got $CP_VERSION"
echo "    ok, crossplane $CP_VERSION"

echo "==> 3. function-patch-and-transform"
kubectl apply -f solution/function.yaml >/dev/null 2>&1 || kubectl apply -f - >/dev/null 2>&1 <<'EOF'
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
[ "$H" = "True" ] || fail "function-patch-and-transform never became healthy"
echo "    ok"

echo "==> 4. XRD (no claim, v2 namespaced XR) + Composition"
kubectl apply -f solution/xrd.yaml >/dev/null || fail "xrd apply"
sleep 2
kubectl get xrd xappconfigs.platform.m10.example.org -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' | grep -q True || fail "xrd not established"
kubectl apply -f solution/composition.yaml >/dev/null || fail "composition apply"
echo "    ok"

echo "==> 5. request the namespaced XR directly (no claim object)"
kubectl apply -f solution/xr.yaml >/dev/null || fail "xr apply"
for i in $(seq 1 20); do
  READY=$(kubectl get xappconfig checkout-service -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$READY" = "True" ] && break
  sleep 3
done
[ "$READY" = "True" ] || fail "XR never went Ready"
kubectl get configmap checkout-service -n default -o jsonpath='{.data.appName}' | grep -q "checkout-service" || fail "composed configmap missing expected data"
echo "    ok, XR Ready, composed ConfigMap has real patched data"

echo "==> 6. numbered teardown: delete XR, then delete cluster"
kubectl delete -f solution/xr.yaml >/dev/null || fail "xr delete"
GC_DONE=0
for i in $(seq 1 20); do
  kubectl get configmap checkout-service -n default >/dev/null 2>&1 || { GC_DONE=1; break; }
  sleep 2
done
[ "$GC_DONE" = "1" ] || fail "composed configmap should have been garbage-collected"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || fail "cluster delete"
docker ps -a --filter "name=$CLUSTER_NAME" --format '{{.Names}}' | grep -q "$CLUSTER_NAME" && fail "orphan cluster container remains"
echo "    ok, XR and composed resource gone, cluster deleted, no orphans"

echo
echo "LAB PASSED -- real kind cluster, real crossplane v2.4.0, namespaced XR (no claim) went Ready, teardown clean"
