# Lab 10: Stand Up a Cluster, Install Crossplane v2, Request a Namespaced XR

**Tier 2** · ~25 min · a real `kind` cluster, real Helm 4, real Crossplane v2. Docker already
required, same as every Tier 1 lab in this course. Numbered teardown at the end.

Everything up to this module ran against Terraform. This lab is the same discipline, propose,
read the diff, apply, on a different substrate: a real Kubernetes control plane.

## Pre Requisites

- `kind`, `kubectl`, `helm`, and `docker` all on `PATH`. Check with:

```
kind version
kubectl version --client
helm version
docker info
```

If `docker info` hangs or errors, stop and fix Docker first, same as every earlier Tier 1 lab.

## The intent

> Give me a namespaced platform resource, `XAppConfig`, that a team can request directly, in
> their own namespace, no separate claim object. Requesting one should compose a real
> `ConfigMap` carrying the app name and environment. Crossplane v2, node image pinned by digest.

## Start the cluster

`file: lab/starter/kind-config.yaml`
```
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: m10-lab
nodes:
  - role: control-plane
    image: kindest/node:v1.31.0@sha256:25a3504b2b340954595fa7a6ed1575ef2edadf5abd83c0776a4308b64bf47c93
```

**Create** the cluster from that config, not a bare `kind create cluster`:

```
kind create cluster --config lab/starter/kind-config.yaml
```

`[ Expected output ]`
```
Creating cluster "m10-lab" ...
 ✓ Ensuring node image (kindest/node:v1.31.0)
 ✓ Preparing nodes
 ✓ Writing configuration
 ✓ Starting control-plane
 ✓ Installing CNI
 ✓ Installing StorageClass
Set kubectl context to "kind-m10-lab"
```

**Verify** it's real, not a mock:

```
kubectl get nodes
```

`[ Expected output ]`
```
NAME                    STATUS   ROLES           AGE   VERSION
m10-lab-control-plane   Ready    control-plane   27s   v1.31.0
```

That digest in the config isn't decoration. Run `docker pull kindest/node:v1.31.0` yourself
and read the `Digest:` line it prints, it's the same one. `latest` and even a version tag can
move under you; a digest can't.

## Install Crossplane v2

```
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
kubectl create namespace crossplane-system
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --version 2.4.0 --wait --timeout 120s
```

`[ Expected output ]`
```
NAME: crossplane
LAST DEPLOYED: ...
NAMESPACE: crossplane-system
STATUS: deployed
Chart Version: 2.4.0
Chart Application Version: 2.4.0
```

**Confirm** it's really v2, not v1, before doing anything else:

```
helm list -n crossplane-system
```

The `APP VERSION` column should read `2.4.0`. If it starts with `1.`, you added the wrong
repo.

## Add a Composition Function

Crossplane v2 compositions run as a pipeline of functions. This lab uses one:

`edit file: (apply directly, no local file needed)`
```
kubectl apply -f - <<'EOF'
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-patch-and-transform
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.9.0
EOF
```

**Wait** for it to report healthy:

```
kubectl get functions.pkg.crossplane.io
```

`[ Expected output ]`
```
NAME                            INSTALLED   HEALTHY   PACKAGE
function-patch-and-transform    True        True      xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.9.0
```

## Write the XRD and Composition

`file: lab/solution/xrd.yaml`
```
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: xappconfigs.platform.m10.example.org
spec:
  scope: Namespaced
  group: platform.m10.example.org
  names:
    kind: XAppConfig
    plural: xappconfigs
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                appName:
                  type: string
                environment:
                  type: string
              required: [appName, environment]
          required: [spec]
```

`spec.scope: Namespaced` is the whole v2 change, in one line. There is no `claimNames` field
anywhere in this XRD. A namespaced XR doesn't need one.

`file: lab/solution/composition.yaml`
```
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xappconfigs.platform.m10.example.org
spec:
  compositeTypeRef:
    apiVersion: platform.m10.example.org/v1alpha1
    kind: XAppConfig
  mode: Pipeline
  pipeline:
    - step: patch-and-transform
      functionRef:
        name: function-patch-and-transform
      input:
        apiVersion: pt.fn.crossplane.io/v1beta1
        kind: Resources
        resources:
          - name: app-configmap
            base:
              apiVersion: v1
              kind: ConfigMap
              metadata: {}
              data: {}
            readinessChecks:
              - type: None
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.name
                toFieldPath: metadata.name
              - type: FromCompositeFieldPath
                fromFieldPath: metadata.namespace
                toFieldPath: metadata.namespace
              - type: FromCompositeFieldPath
                fromFieldPath: spec.appName
                toFieldPath: data.appName
              - type: FromCompositeFieldPath
                fromFieldPath: spec.environment
                toFieldPath: data.environment
```

`readinessChecks: [{type: None}]` matters here: a plain `ConfigMap` carries no status
condition Crossplane can watch, so without this the XR sits stuck at `READY False` forever,
waiting for a signal that will never come. Leave it out and re-run the next step to see
that for yourself.

**Apply** both:

```
kubectl apply -f lab/solution/xrd.yaml
kubectl apply -f lab/solution/composition.yaml
```

## Request the XR, no claim object

`file: lab/solution/xr.yaml`
```
apiVersion: platform.m10.example.org/v1alpha1
kind: XAppConfig
metadata:
  name: checkout-service
  namespace: default
spec:
  appName: checkout-service
  environment: staging
```

Read this the way you'd read a `terraform plan`, before applying it:

```
kubectl diff -f lab/solution/xr.yaml
```

**Apply** it:

```
kubectl apply -f lab/solution/xr.yaml
```

**Verify** it goes `Ready`:

```
kubectl get xappconfig checkout-service -n default
```

`[ Expected output ]`
```
NAME               SYNCED   READY   COMPOSITION                            AGE
checkout-service   True     True    xappconfigs.platform.m10.example.org   43s
```

**Confirm** the composed `ConfigMap` carries the real patched values:

```
kubectl get configmap checkout-service -n default -o yaml
```

`[ Expected output ]`
```
data:
  appName: checkout-service
  environment: staging
kind: ConfigMap
metadata:
  name: checkout-service
  namespace: default
  ownerReferences:
  - apiVersion: platform.m10.example.org/v1alpha1
    controller: true
    kind: XAppConfig
    name: checkout-service
```

That `ownerReferences` block is doing real work, not just bookkeeping. It's what makes the
next step possible.

## Teardown

**1. Delete the XR:**

```
kubectl delete -f lab/solution/xr.yaml
```

**Confirm** the composed `ConfigMap` went with it, garbage-collected via the owner reference
above, no manual cleanup needed:

```
kubectl get configmap checkout-service -n default
```

`[ Expected output ]`
```
Error from server (NotFound): configmaps "checkout-service" not found
```

**2. Delete the cluster:**

```
kind delete cluster --name m10-lab
```

`[ Expected output ]`
```
Deleting cluster "m10-lab" ...
Deleted nodes: ["m10-lab-control-plane"]
```

**Confirm** no orphan container is left behind:

```
docker ps -a --filter "name=m10-lab"
```

Empty output means clean.

#### Exercise

Change `readinessChecks` back to the default (delete that block entirely from
`composition.yaml`), re-apply, and request a second XR. Watch it stay `READY False`
indefinitely. Explain, in your own words, why a plain `ConfigMap` needs an explicit
`type: None` readiness check and a resource with its own status conditions usually
wouldn't.

#### Summary

You ran the exact same discipline this course has used since module one, propose, read the
diff, gate the apply, on a real Kubernetes cluster instead of Terraform. `kind` gave you a
real control plane pinned by digest. Crossplane v2 turned a namespaced XR into a real
composed resource, no claim object in the way. M11 picks this cluster back up and puts a
GitOps controller in front of it.

##### Reading List

- [kind: node image documentation](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Crossplane v2: composite resources](https://docs.crossplane.io/latest/concepts/composite-resources/)
- `reading/concepts.md` in this module: why Crossplane v2 removed claims, and what a
  namespace boundary now does instead

##### Search Keywords

- kind, node image digest, kindest/node
- helm 4, helm install, crossplane-stable
- crossplane v2, XRD, Composition, XR, namespaced composite resource
- function-patch-and-transform, readinessChecks
- kubectl diff, reconcile loop
