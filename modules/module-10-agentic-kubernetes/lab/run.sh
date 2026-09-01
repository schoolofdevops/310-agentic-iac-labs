set -uo pipefail
cd "$(dirname "$0")"
export PATH="/Users/gshah/.rd/bin:$PATH"
fail(){ echo "FAIL: $*" >&2; kind delete cluster --name m10-lab >/dev/null 2>&1; exit 1; }

CLUSTER_NAME="m10-lab"
NODE_IMAGE="kindest/node:v1.31.0@sha256:25a3504b2b340954595fa7a6ed1575ef2edadf5abd83c0776a4308b64bf47c93"

echo "==> 1. kind cluster up, node image pinned by digest"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
kind create cluster --config starter/kind-config.yaml >/tmp/m10-kind.log 2>&1 || { cat /tmp/m10-kind.log; fail "kind create cluster"; }
kubectl --context "kind-$CLUSTER_NAME" get nodes | grep -q "$CLUSTER_NAME" || fail "node not present"
echo "    ok"

echo "==> 2. crossplane v2 via real helm chart"
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
kubectl --context "kind-$CLUSTER_NAME" create namespace crossplane-system >/dev/null 2>&1
helm install crossplane crossplane-stable/crossplane --kube-context "kind-$CLUSTER_NAME" --namespace crossplane-system --version 2.4.0 --wait --timeout 300s >/tmp/m10-helm.log 2>&1 || { cat /tmp/m10-helm.log; fail "crossplane install"; }
CP_VERSION=$(helm list --kube-context "kind-$CLUSTER_NAME" -n crossplane-system -o json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['app_version'])")
[[ "$CP_VERSION" == 2.* ]] || fail "expected crossplane v2, got $CP_VERSION"
echo "    ok, crossplane $CP_VERSION"

echo "==> 3. function-patch-and-transform"
kubectl --context "kind-$CLUSTER_NAME" apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-patch-and-transform
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.9.0
EOF
for i in $(seq 1 30); do
  H=$(kubectl --context "kind-$CLUSTER_NAME" get functions.pkg.crossplane.io function-patch-and-transform -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null)
  [ "$H" = "True" ] && break
  sleep 3
done
[ "$H" = "True" ] || fail "function-patch-and-transform never became healthy"
echo "    ok"

echo "==> 4. warm-up: XRD (no claim, v2 namespaced XR) + Composition"
kubectl --context "kind-$CLUSTER_NAME" apply -f solution/xrd.yaml >/dev/null || fail "xrd apply"
sleep 2
kubectl --context "kind-$CLUSTER_NAME" get xrd xappconfigs.platform.m10.example.org -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' | grep -q True || fail "xrd not established"
kubectl --context "kind-$CLUSTER_NAME" apply -f solution/composition.yaml >/dev/null || fail "composition apply"
echo "    ok"

echo "==> 5. warm-up: request the namespaced XR directly (no claim object)"
kubectl --context "kind-$CLUSTER_NAME" apply -f solution/xr.yaml >/dev/null || fail "xr apply"
for i in $(seq 1 20); do
  READY=$(kubectl --context "kind-$CLUSTER_NAME" get xappconfig checkout-service -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$READY" = "True" ] && break
  sleep 3
done
[ "$READY" = "True" ] || fail "XR never went Ready"
kubectl --context "kind-$CLUSTER_NAME" get configmap checkout-service -n default -o jsonpath='{.data.appName}' | grep -q "checkout-service" || fail "composed configmap missing expected data"
echo "    ok, XR Ready, composed ConfigMap has real patched data"
kubectl --context "kind-$CLUSTER_NAME" delete -f solution/xr.yaml >/dev/null || fail "warm-up xr delete"

echo "==> 6. layer one: raw manifests, a real Postgres by hand"
kubectl --context "kind-$CLUSTER_NAME" create namespace dbaas-manual >/dev/null 2>&1
kubectl --context "kind-$CLUSTER_NAME" apply -f manifests/postgres-secret.yaml -f manifests/postgres-service.yaml -f manifests/postgres-statefulset.yaml >/dev/null || fail "manual manifests apply"
kubectl --context "kind-$CLUSTER_NAME" -n dbaas-manual rollout status statefulset/postgres --timeout=120s >/dev/null || fail "manual statefulset never ready"
kubectl --context "kind-$CLUSTER_NAME" -n dbaas-manual exec postgres-0 -- pg_isready -U appuser -d appdb | grep -q "accepting connections" || fail "manual postgres not accepting connections"
echo "    ok, real postgres:16-alpine accepting connections from raw manifests"

echo "==> 7. layer two: the same capability, packaged as a Helm chart"
helm install billing-db ./charts/postgres-db --kube-context "kind-$CLUSTER_NAME" -n dbaas-helm --create-namespace --set dbName=billing_service --wait --timeout 90s >/dev/null || fail "helm chart install"
kubectl --context "kind-$CLUSTER_NAME" -n dbaas-helm exec billing-db-postgres-0 -- psql -U appuser -d billing_service -c "SELECT 1;" >/dev/null || fail "helm-installed postgres not queryable"
echo "    ok, helm-installed instance real and queryable"

echo "==> 8. layer three: request a database as one namespaced XR, no Helm values, no claim"
kubectl --context "kind-$CLUSTER_NAME" apply -f solution/db-xrd.yaml >/dev/null || fail "db-xrd apply"
sleep 2
kubectl --context "kind-$CLUSTER_NAME" get xrd xdatabases.platform.m10.example.org -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' | grep -q True || fail "db-xrd not established"
kubectl --context "kind-$CLUSTER_NAME" apply -f solution/db-composer-rbac.yaml >/dev/null || fail "db-composer-rbac apply"
kubectl --context "kind-$CLUSTER_NAME" apply -f solution/db-composition.yaml >/dev/null || fail "db-composition apply"
kubectl --context "kind-$CLUSTER_NAME" apply -f solution/db-xr.yaml >/dev/null || fail "db-xr apply"
for i in $(seq 1 30); do
  LINE=$(kubectl --context "kind-$CLUSTER_NAME" get xdatabase billing -n default --no-headers 2>/dev/null)
  SYNCED=$(echo "$LINE" | awk '{print $2}')
  READY=$(echo "$LINE" | awk '{print $3}')
  [ "$SYNCED" = "True" ] && [ "$READY" = "True" ] && break
  sleep 5
done
[ "$SYNCED" = "True" ] && [ "$READY" = "True" ] || fail "XDatabase billing never went Synced+Ready"
kubectl --context "kind-$CLUSTER_NAME" -n default exec billing-postgres-0 -- psql -U appuser -d billing_service -c "SELECT 1;" >/dev/null || fail "crossplane-composed postgres not queryable"
echo "    ok, XDatabase composed a real StatefulSet+Service+Secret, real postgres queryable"

echo "==> 9. teardown"
kubectl --context "kind-$CLUSTER_NAME" delete -f solution/db-xr.yaml >/dev/null || fail "db-xr delete"
GC_DONE=0
for i in $(seq 1 20); do
  kubectl --context "kind-$CLUSTER_NAME" -n default get statefulset billing-postgres >/dev/null 2>&1 || { GC_DONE=1; break; }
  sleep 2
done
[ "$GC_DONE" = "1" ] || fail "composed statefulset should have been garbage-collected"
helm uninstall billing-db --kube-context "kind-$CLUSTER_NAME" -n dbaas-helm >/dev/null 2>&1 || true
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || fail "cluster delete"
docker ps -a --filter "name=$CLUSTER_NAME" --format '{{.Names}}' | grep -q "$CLUSTER_NAME" && fail "orphan cluster container remains"
echo "    ok, XR and composed resource gone, cluster deleted, no orphans"

echo
echo "LAB PASSED -- real kind cluster, real crossplane v2.4.0, a database-as-a-service capability delivered three real ways: raw manifests, a Helm chart, and a namespaced Crossplane XR, teardown clean"
