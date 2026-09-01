# Lab 11: Wire the Pipeline Into CI, Reconcile With GitOps

**Tier 2** · ~25 min · a real GitHub Actions workflow, a real pull request, a real Argo CD
install reconciling a real `kind` cluster. Docker required, same as every earlier Tier 1/2 lab.
Numbered teardown at the end.

M10 stood up a real cluster and requested a namespaced resource by hand. This lab automates the
gate from M09 into CI, and puts a real GitOps controller on the other side of `merge`.

## Pre Requisites

- `kind`, `kubectl`, `helm`, `docker`, and `gh` all on `PATH`, and `gh auth status` logged in.
  Check with:

```
kind version
kubectl version --client
helm version
docker info
gh auth status
```

If `docker info` hangs or errors, stop and fix Docker first, same as every earlier lab.

## The intent

> Take the checkov-style gate from M09 and make it run on its own, on every pull request. Once a
> pull request merges, a real controller should reconcile a real cluster to match, with nobody
> running `kubectl apply`.

## Add the CI workflow

`file: .github/workflows/m11-pipeline-demo.yml`
```
name: M11 pipeline demo

on:
  pull_request:
    paths:
      - 'modules/module-11-agentic-gitops/lab/pipeline-demo/**'

jobs:
  gate:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: modules/module-11-agentic-gitops/lab/pipeline-demo
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.8
      - name: terraform fmt
        run: terraform fmt -check -diff
      - name: terraform init
        run: terraform init -backend=false -input=false
      - name: terraform validate
        run: terraform validate
      - name: checkov
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: modules/module-11-agentic-gitops/lab/pipeline-demo
          quiet: true
          compact: true
```

The `paths:` filter matters. Without it, every pull request in the repo would trigger this
workflow, including ones that never touch this module.

## Open a real PR with a real flaw

`file: lab/pipeline-demo/main.tf`
```
variable "webhook_token" {
  description = "Token for the pipeline's status webhook"
  type        = string
  default     = "AKIAABCDEFGHIJKLMNOP"
}
```

**Push** a branch with that file, and **open** a real pull request. This is the same finding
from Lab 1, on purpose: a plaintext key sitting where a scanner will actually see it.

```
git checkout -b m11-gitops-lab-demo
git add .github/workflows/m11-pipeline-demo.yml modules/module-11-agentic-gitops/lab/pipeline-demo
git commit -m "M11 lab demo: CI-gated pipeline snippet"
git push -u origin m11-gitops-lab-demo
gh pr create --title "M11 lab demo" --body "CI should catch the hardcoded key"
```

**Watch** the workflow run, and **read** the real failure:

```
gh run watch --exit-status
```

`[ Expected output ]`
```
X gate in 25s
  ✓ terraform fmt
  ✓ terraform init
  ✓ terraform validate
  X checkov

X CKV_SECRET_2: "AWS Access Key"
```

Nobody ran `checkov` by hand. A pull request did, on its own, and it failed for a real reason.

## Fix it, re-push, watch it go green

`edit file: lab/pipeline-demo/main.tf`
```
variable "webhook_token" {
  description = "Token for the pipeline's status webhook. Set via TF_VAR_webhook_token, never a default."
  type        = string
  sensitive   = true
}
```

```
git add -A
git commit -m "fix hardcoded secret, mark sensitive instead"
git push
gh run watch --exit-status
```

`[ Expected output ]`
```
Run M11 pipeline demo has already completed with 'success'
```

## Merge

This is the one manual step left in the whole loop:

```
gh pr merge --squash --delete-branch
```

`[ Expected output ]`
```
✓ Squashed and merged pull request
```

## Stand up the cluster, install Argo CD

`file: lab/starter/kind-config.yaml`
```
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: m11-lab
nodes:
  - role: control-plane
    image: kindest/node:v1.31.0@sha256:25a3504b2b340954595fa7a6ed1575ef2edadf5abd83c0776a4308b64bf47c93
```

```
kind create cluster --name m11-lab --config lab/starter/kind-config.yaml
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=available --timeout=240s \
  deployment/argocd-repo-server deployment/argocd-server
```

`--server-side --force-conflicts` isn't decoration either. Argo CD's own install manifest is
big enough that a plain client-side `kubectl apply` fails outright with an annotation-size
error the first time.

## Point Argo CD at the real, merged repo

`file: lab/solution/argocd-app.yaml`
```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: m11-gitops-demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/schoolofdevops/310-agentic-iac-labs.git
    targetRevision: main
    path: modules/module-11-agentic-gitops/lab/gitops-demo
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

This is a real, public repo, this course's own `310-agentic-iac-labs`, and `lab/gitops-demo/`
is a plain `ConfigMap` manifest merged there just now, the same repo you opened a pull request
against a moment ago.

```
kubectl apply -f lab/solution/argocd-app.yaml
```

**Verify** it goes `Synced` and `Healthy`:

```
kubectl get application m11-gitops-demo -n argocd
```

`[ Expected output ]`
```
NAME               SYNC STATUS   HEALTH STATUS
m11-gitops-demo    Synced        Healthy
```

**Confirm** the `ConfigMap` really landed:

```
kubectl get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}'
```

`[ Expected output ]`
```
reconciled by GitOps, not kubectl apply
```

## See self-heal for real

**Tamper** with the resource directly, the way someone might by accident:

```
kubectl patch configmap m11-gitops-demo -n default --type merge \
  -p '{"data":{"message":"manually tampered, should get corrected"}}'
kubectl get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}'
```

`[ Expected output ]`
```
manually tampered, should get corrected
```

**Wait** a few seconds, and **check** again:

```
kubectl get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}'
```

`[ Expected output ]`
```
reconciled by GitOps, not kubectl apply
```

Nobody ran anything the second time. The controller noticed the drift and corrected it on its
own. That's the mechanical difference from Terraform's one-shot model, felt directly instead of
just read about.

## Teardown

**1. Remove the Argo CD application:**

```
kubectl delete -f lab/solution/argocd-app.yaml
```

**2. Delete the cluster:**

```
kind delete cluster --name m11-lab
```

**Confirm** no orphan container is left behind:

```
docker ps -a --filter "name=m11-lab"
```

Empty output means clean.

#### Exercise

Point Argo CD's `syncPolicy` at manual instead of automated (`syncPolicy: {}` with no
`automated:` block), tamper with the ConfigMap the same way, and watch nothing get corrected
until you run `argocd app sync` yourself. Explain, in your own words, why `automated.selfHeal`
is what actually makes this step 5 rather than a still-manual step 4 with extra steps.

#### Summary

You wired the M09 pipeline into CI, watched it catch a real secret automatically, merged the
one thing left for a human to decide, and watched a real GitOps controller reconcile a real
cluster from that merge, unattended, including correcting a real manual tamper on its own.
That's step 5, supervised autonomy, for real: you reviewed the pull request's outcome, not
each gate or each sync event. M12 is where this course asks what happens when the loop itself,
not just one pipeline, runs across many agents at once.

##### Reading List

- [Argo CD: core concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts/)
- [GitHub Actions: workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- `reading/concepts.md` in this module: why synced and healthy are different questions, and
  exactly what step 5 does and doesn't mean

##### Search Keywords

- github actions, pull_request paths filter
- checkov-action, CKV_SECRET_2
- argocd, Application, syncPolicy, automated, selfHeal
- kind, server-side apply, force-conflicts
- gitops, reconcile, drift correction
