# Lab 11: An Agent Proposes, a Pipeline Reviews, You Merge, GitOps Delivers

**Tier 2** · ~25 min · a real GitHub Actions workflow, a real agent-opened pull request, a real
Argo CD install reconciling a real `kind` cluster. Docker required, same as every earlier
Tier 1/2 lab. Numbered teardown at the end.

**The project:** a real, working delivery pipeline for one small infrastructure repo, one that
lets an agent propose a production change and reach a real cluster without a human ever running
`terraform apply` or `kubectl apply` by hand, and without a human reading every line the agent
wrote either. You will build it in four stages, each a separate job, each doing one thing:

1. Wire an automated gate onto GitHub pull requests, so it runs whether or not anyone is
   watching.
2. Let an agent propose a real change and open a real pull request, no human touching the diff
   first.
3. Watch that gate catch a real mistake in the agent's own commit, and send a second agent in to
   fix the real cause.
4. Merge the one outcome a human actually reviews, then hand the apply itself to a real GitOps
   controller reconciling a real cluster, including correcting a manual tamper on its own.

M10 stood up a cluster and requested a namespaced resource by hand. This lab is not really about
GitOps mechanics, those are the easy part, they're stage 4 above. It's about what makes an
agent's production change safe to ship without a human reading every line: an automated gate
that catches the agent's own mistake, a second agent that fixes the real cause once it sees the
gate's real output, and a human who reviews one outcome instead of a diff. GitOps is what
applies the result afterward, unattended and correctly. It's the last link in the chain, not the
whole subject.

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
      - name: trivy
        uses: aquasecurity/trivy-action@v0.36.0
        with:
          scan-type: config
          scan-ref: modules/module-11-agentic-gitops/lab/pipeline-demo
          severity: HIGH,CRITICAL
          exit-code: 1
      - name: checkov
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: modules/module-11-agentic-gitops/lab/pipeline-demo
          quiet: true
          compact: true
```

The `paths:` filter matters. Without it, every pull request in the repo would trigger this
workflow, including ones that never touch this module.

This is the same fmt/validate/Trivy/Checkov shape as M09's `pipeline.sh`, minus the policy
and cost stages, which need a `policy/` directory and an Infracost API key this toy module
doesn't carry. Worth saying plainly: this module's `local_file` resources have nothing
Trivy's cloud/container checks look for, so it runs clean here, 0 findings, every time. That
is not a wasted stage. It is the same command M09 ran against real AWS resources and found 7
HIGH/CRITICAL findings, wired to run automatically now, on infrastructure that happens not to
trip it. Checkov is what actually catches this lab's finding, next.

## Let the agent propose the change, not you

Every earlier lab in this course had you drive the agent through each step yourself. This one
is different on purpose: the thing being tested is whether a *pipeline*, not a human proofreading
a diff, catches a mistake the agent makes on its own. So the agent opens this pull request, not
you.

**Ask** Claude Code, from this repo, to make a real, ordinary-sounding change and open a real PR
for it:

```
claude -p "Add a new Terraform variable named signing_key_id to
modules/module-11-agentic-gitops/lab/pipeline-demo/main.tf. Type string, described as 'Key ID
used to sign outbound webhook payloads', default value a fake but realistic AWS access key ID
literal, the way a developer in a hurry might write it. Add a local_file resource named
webhook_signing_config that writes SIGNING_KEY_ID=\${var.signing_key_id} to
\${path.module}/rendered/signing.env, matching the existing pipeline_config resource's pattern.
Commit on the current branch, push, and open a real PR against
schoolofdevops/310-agentic-iac-labs with gh pr create." \
  --permission-mode acceptEdits --allowedTools "Read,Edit,Bash(git *),Bash(gh *)"
```

`[ Expected output ]`
```
Done. Var + resource added, committed (89c33af), pushed, PR opened:
https://github.com/schoolofdevops/310-agentic-iac-labs/pull/4

Note: default value baked-in AKIA-pattern literal, intentional per lab demo, but flag: real
Trivy config-scan stage (from M11 pipeline) should catch this as hardcoded secret. That's
likely point of demo.
```

Read that note again. The agent noticed its own mistake on the way out and said so, it just
didn't stop itself from committing it anyway, because nothing in its instructions told it to.
That's exactly the gap a gate closes and a polite disclaimer doesn't.

**Watch** the real pull request's real CI run:

```
gh pr checks 4 --watch
```

`[ Expected output ]`
```
JOBS
X gate in 43s
  ✓ terraform fmt
  ✓ terraform init
  ✓ terraform validate
  ✓ trivy
  X checkov

X CKV_SECRET_2: "AWS Access Key"
```

Nobody ran `checkov` by hand, and nobody reviewed the agent's diff before it went out. A pull
request did the reviewing, automatically, and it failed for a real reason: the same
`CKV_SECRET_2` finding this course has used since Lab 1, this time on an agent's own commit.

## Send the failure back to the agent

**Ask** a second, separate agent session to fix it, using nothing but the real CI output as
context:

```
claude -p "You are on git branch m11-agent-proposed-demo, PR
schoolofdevops/310-agentic-iac-labs#4. Its CI just failed: checkov reported CKV_SECRET_2 'AWS
Access Key' against modules/module-11-agentic-gitops/lab/pipeline-demo/main.tf. Read that file,
find the cause (signing_key_id has a hardcoded default), fix it: remove the default, mark it
sensitive = true, update the description to say how it should actually be set. Do not touch the
unrelated webhook_token variable. Commit and push." \
  --permission-mode acceptEdits --allowedTools "Read,Edit,Bash(git *)"
```

`[ Expected output ]`
```
Done. cb92c25 pushed. signing_key_id now no default, sensitive=true, desc says set via
TF_VAR_signing_key_id. webhook_token untouched. CKV_SECRET_2 should clear on next CI run.
```

**Watch** the same PR's CI run again:

```
gh pr checks 4 --watch
```

`[ Expected output ]`
```
JOBS
✓ gate in 26s
  ✓ terraform fmt
  ✓ terraform init
  ✓ terraform validate
  ✓ trivy
  ✓ checkov
```

## Merge

This is the one manual step left in the whole loop, and notice what you're actually reviewing:
not `terraform fmt`, not the trivy run, not the checkov run, not even the diff line by line.
You're reviewing the outcome, a pull request that went from failing to passing for a documented
reason, and deciding whether that's good enough to ship:

```
gh pr merge 4 --squash --delete-branch
```

`[ Expected output ]`
```
✓ Squashed and merged pull request #4 (M11 lab demo: agent-proposed webhook signing config)
```

Two agent sessions proposed and fixed this change. Zero human edits touched the Terraform. One
human read a passing pull request and clicked merge. That's the whole shape of safe agentic
delivery to prod: an agent's mistake reached a pipeline before it reached a person, the pipeline
caught it and said exactly why, a second agent session fixed the actual cause instead of the
symptom, and the only judgment call left for a human was "is this diff, now that it's green, the
right thing to ship." Stages 1 through 3 of the project are done. What's left is stage 4, the
part where the merged result actually reaches a running cluster.

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
kubectl --context kind-m11-lab create namespace argocd
kubectl --context kind-m11-lab apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl --context kind-m11-lab -n argocd wait --for=condition=available --timeout=240s \
  deployment/argocd-repo-server deployment/argocd-server
```

`--server-side --force-conflicts` isn't decoration either. Argo CD's own install manifest is
big enough that a plain client-side `kubectl apply` fails outright with an annotation-size
error the first time.

`--context kind-m11-lab` on every command from here on isn't decoration either. `kind create
cluster` changes your kubeconfig's current-context globally, so if you (or an earlier module)
still have another kind cluster around, creating this one can silently leave `kubectl` pointed
at the wrong cluster. Pinning the context makes every command below correct regardless of what
else is running on your machine.

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
kubectl --context kind-m11-lab apply -f lab/solution/argocd-app.yaml
```

**Verify** it goes `Synced` and `Healthy`:

```
kubectl --context kind-m11-lab get application m11-gitops-demo -n argocd
```

`[ Expected output ]`
```
NAME               SYNC STATUS   HEALTH STATUS
m11-gitops-demo    Synced        Healthy
```

**Confirm** the `ConfigMap` really landed:

```
kubectl --context kind-m11-lab get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}'
```

`[ Expected output ]`
```
reconciled by GitOps, not kubectl apply
```

## See self-heal for real

**Tamper** with the resource directly, the way someone might by accident:

```
kubectl --context kind-m11-lab patch configmap m11-gitops-demo -n default --type merge \
  -p '{"data":{"message":"manually tampered, should get corrected"}}'
kubectl --context kind-m11-lab get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}'
```

`[ Expected output ]`
```
manually tampered, should get corrected
```

**Wait** a few seconds, and **check** again:

```
kubectl --context kind-m11-lab get configmap m11-gitops-demo -n default -o jsonpath='{.data.message}'
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
kubectl --context kind-m11-lab delete -f lab/solution/argocd-app.yaml
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

The project is done: a real delivery pipeline where an agent proposed a real change and opened a
real pull request, a pipeline, not a human, caught the agent's own hardcoded secret and said
exactly why, a second agent fixed the real cause from that real failure, not a guess, a human
reviewed one outcome, a pull request gone from red to green, and merged it, the only manual step
in the whole chain, and a real GitOps controller then reconciled a real cluster from that merge,
unattended, including correcting a real manual tamper on its own. That's step 5, supervised
autonomy, for real: you reviewed outcomes, propose and merge, not each gate, each fix, or each
sync event in between. M12 is where this course asks what happens when the loop itself, not just
one pipeline, runs across many agents at once.

##### Reading List

- [Argo CD: core concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts/)
- [GitHub Actions: workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- `reading/concepts.md` in this module: why propose, review, merge, and apply are four separate
  jobs, and exactly what step 5 does and doesn't mean

##### Search Keywords

- agent-proposed pull request, propose then review then merge then apply
- github actions, pull_request paths filter
- trivy config scan, checkov-action, CKV_SECRET_2
- argocd, Application, syncPolicy, automated, selfHeal
- kind, server-side apply, force-conflicts
- gitops, reconcile, drift correction
