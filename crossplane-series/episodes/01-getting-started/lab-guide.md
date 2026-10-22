# Crossplane Getting Started — Infrastructure as Kubernetes APIs
## Lab Guide & Runbook

> **Episode 1 of the Crossplane series.**
> Terraform automates creating infrastructure. Crossplane *runs* it —
> controllers that reconcile your databases, buckets, namespaces and
> cloud resources forever, from the same API server that runs your pods.
> In this episode we install it, fight it, and then use it to publish
> our own platform API.

**Quick demo:** `make demo-ep01` (guided, interactive) · **Cleanup:** `make cleanup-ep01`

**Two ways to run this demo:**

- **Guided** — `make demo-ep01`: the script walks every step with pauses
  between them (good for a first pass; every command is printed as it runs)
- **Manual, section by section** — follow Sections 7–17 below and run each
  command by hand. Better for recording: you control the camera timing at
  every step, pause to explain, and can re-take any section without
  rerunning the whole script. **Every command the script runs is in this
  guide.**

All manual commands assume you are in the repo root
(`crossplane-series/`) with the lab kubeconfig exported:

```bash
cd ~/Proxmox/homeops/crossplane-series
export KUBECONFIG="$HOME/.kube/config-k8suth"
```

---

## Table of Contents

- [1. Episode Overview](#1-episode-overview)
- [2. Learning Objectives](#2-learning-what-youll-be-able-to-do)
- [3. Lab Architecture](#3-lab-architecture)
- [4. Prerequisites](#4-prerequisites)
- [5. Concept Deep-Dive A — The Problem, and Two Mental Models](#5-concept-deep-dive-a--the-problem-and-two-mental-models)
- [6. Concept Deep-Dive B — Crossplane's Building Blocks](#6-concept-deep-dive-b--crossplanes-building-blocks)
- [7. Install Crossplane Core](#7-install-crossplane-core)
- [8. What Just Got Installed — a Tour](#8-what-just-got-installed--a-tour)
- [9. Install a Provider (and what a provider actually IS)](#9-install-a-provider-and-what-a-provider-actually-is)
- [10. Credentials: ProviderConfig and InjectedIdentity](#10-credentials-providerconfig-and-injectedidentity)
- [11. Your First Managed Resources](#11-your-first-managed-resources)
- [12. The Reconcile Loop — Watch It Work (Drift Fight)](#12-the-reconcile-loop--watch-it-work-drift-fight)
- [13. Control the Lifecycle (updates, removalPolicy, orphan vs delete)](#13-control-the-lifecycle-updates-removalpolicy-orphan-vs-delete)
- [14. Publish Your Own API — the XRD](#14-publish-your-own-api--the-xrd)
- [15. The Composition — a Recipe Made of Functions](#15-the-composition--a-recipe-made-of-functions)
- [16. Use the API — Create, Trace, Update, Delete a WebApp](#16-use-the-api--create-trace-update-delete-a-webapp)
- [17. Crossplane vs Terraform — the Full Comparison](#17-crossplane-vs-terraform--the-full-comparison)
- [18. Cleanup / Reset](#18-cleanup--reset)
- [Troubleshooting](#troubleshooting)
- [Appendix A — Crossplane v1 vs v2 (why old tutorials mislead)](#appendix-a--crossplane-v1-vs-v2-why-old-tutorials-mislead)
- [Appendix B — Glossary](#appendix-b--glossary)

---

## 1. Episode Overview

This is the *getting started* episode, and we treat that seriously: by the
end you will have touched every core Crossplane concept, on a real cluster,
with your own hands.

The arc:

1. **Install** Crossplane into the existing K3s lab (one Helm release)
2. **Understand packages** — install a provider and composition functions,
   and see that they are CRDs + controllers, delivered as images
3. **Manage a resource** — a namespace and ConfigMap via provider-kubernetes,
   with zero credentials
4. **Fight the control plane** — delete things behind its back, watch it heal
5. **Own the lifecycle** — update specs, learn `removalPolicy` (orphan vs delete)
6. **Publish an API** — XRD + Composition → a new `kind: WebApp` that any
   team can create, which composes a whole environment
7. **Operate it** — trace, debug, clean teardown
8. **Judge it** — the honest Crossplane-vs-Terraform comparison

| What you keep from this episode | Where |
|---|---|
| A running Crossplane v2 in the lab | `crossplane-system` namespace |
| A working provider with no credentials | provider-kubernetes + InjectedIdentity |
| Your own platform API | XRD `webapps.demo.crossplane.io` + Composition `webapp-standard` |
| A repeatable demo | `make demo-ep01` / this guide |

## 2. Learning: What You'll Be Able To Do

By the end of this episode you can:

- Explain the difference between a **pipeline** (Terraform: plan → apply →
  exit) and a **control plane** (Crossplane: controllers reconcile forever)
- Explain why Crossplane has **no state file**, and what it uses instead
  (the API server + level-triggered reconciliation)
- Name all four Crossplane **package types** (Provider, Configuration,
  Function — and what each delivers)
- Install Crossplane and a provider, and explain the **conditions**
  (`Installed`, `Healthy`) you watched along the way
- Read a **managed resource** spec (`forProvider`, `providerConfigRef`,
  `removalPolicy`) and its conditions (`Ready`, `Synced`)
- Explain **drift** in both worlds, and demonstrate Crossplane healing it live
- Choose between `removalPolicy: Delete` and `Orphan` and say when each fits
- Explain what an **XRD** is, what a **Composition** is, and what a
  **composition function** pipeline does
- Create, trace, update, and safely delete a **composite resource** (WebApp)
- Debug Crossplane: `crossplane beta trace`, provider logs, events, conditions
- Make the **Crossplane vs Terraform** call for a given team, honestly

## 3. Lab Architecture

Same 3-node K3s cluster as the under-the-hood series (Terraform built it —
keep that irony in your pocket for segment 17):

```
                     ┌────────────────────────────────────┐
                     │  master (192.168.1.81, pve4)       │
                     │  K3s server (API + etcd + sched)  │
                     │  Prometheus :30900 / Grafana :30300│
                     │  crossplane core pod               │
                     │  provider-kubernetes pod           │
                     │  function pods (×2)                │
                     └────────────────────────────────────┘
                          ▲                ▲
             reconcile    │   reconcile    │   reconcile
             (namespace)  │  (configmap)  │   (WebApp XR)
                          │                │
        ┌─────────────────┴───┐   ┌───────┴──────────────┐
        │  worker-1 (.82, pve2)│   │  worker-2 (.83, pve3) │
        │  demo pods            │   │  demo pods            │
        └───────────────────────┘   └──────────────────────┘

  crossplane-system namespace:
    crossplane         — core controllers + package manager
    provider-kubernetes— watches Object resources, talks to the API server
                         (in this episode: as its own ServiceAccount)
    function-p&t       — used ONLY when a WebApp is being composed
    function-auto-ready— marks the WebApp Ready when composed resources are
```

Three controller loops to keep straight in your head (and on camera):

1. **Core Crossplane** — watches `Provider`/`Function` packages and XRD
   definitions (installs/uninstalls them)
2. **Provider controller** — watches managed resources (`Object`s) and makes
   reality match them
3. **Composite/Composition controller** — watches WebApp XRs and, when one
   appears, runs the function pipeline to create composed resources — which
   are themselves watched by loop 2. **A chain of loops.**

## 4. Prerequisites

- The under-the-hood lab is up: `cd ../k8s-under-the-hood && make verify`
- `kubectl` v1.36+, `helm` v3.14+
- `crossplane` CLI v2 (`brew install crossplane-cli`) — used for
  `crossplane beta trace` and offline rendering; the demo degrades
  gracefully if it's missing, but install it
- Internet from controller (`charts.crossplane.io`) and from nodes
  (`xpkg.upbound.io`, ghcr.io)
- Versions pinned in `lab/versions.env` — check them before recording:
  `helm search repo crossplane-stable/crossplane --versions | head -3`

> **Manifest/version caveat:** this guide targets **Crossplane v2**
> (`apiextensions.crossplane.io/v2`, namespaced XRs, `mode: Pipeline`
> compositions, `removalPolicy`). If your installed chart is a different
> minor, dry-run everything offline first:
> `crossplane beta render manifests/04-webapp.yaml manifests/03-composition.yaml`
> Fix schema mismatches *before* recording, never live.

### One-time install of the series components

Guided:

```bash
make crossplane-install   # does everything in Sections 7, 9, 10 + waits
make verify               # health check
```

Manual — Sections 7, 9, 10 below, every command spelled out.

---

## 5. Concept Deep-Dive A — The Problem, and Two Mental Models

*(No terminal for this section — diagram + narration. Scripts: narration.md Phase 2–3.)*

### The problem with infrastructure-as-a-pipeline

Terraform's workflow, honestly stated:

```
human → terraform plan → review → terraform apply → [state file updated] → done
        └── one shot. The world is now correct... until it isn't.
```

Three structural consequences:

1. **The state file is the source of truth, and it's a liability.** Lock it
   (team collisions), store it (S3/backends), back it up, never commit it,
   and pray nobody edits a resource in the console (drift!). Every team
   eventually writes "run `terraform plan` in CI and alert on exit code 2" —
   reinventing a drift detector as a cron job.
2. **Correctness ends when the apply ends.** Nothing is watching. A console
   click, a helpful teammate's `kubectl edit`, a failed half-apply — the
   pipeline doesn't know until the next plan.
3. **The consumer reads Terraform.** Modules hide complexity, but the
   developer still writes HCL, still needs provider credentials, still
   waits for a pipeline. Your platform is files, not an API.

### The control plane model

Crossplane's answer — and it's the same answer Kubernetes itself gives:

```
human → kubectl apply → API server (etcd) → controllers watch → reconcile →
        └── forever. Desired state is stored, observed, and ENFORCED continuously.
```

- **Desired state lives in the API server.** No separate state file —
  `kubectl get` *is* `terraform state list`. etcd already solved storage,
  watch, and audit.
- **Controllers are level-triggered.** They don't respond to *events*
  ("someone ran apply"); they respond to *state* ("actual ≠ desired"). This
  is Episode-1-of-K8s material: it's the Deployment controller, applied to
  infrastructure. If you've seen the control-loop Short, you already know
  the pattern — Crossplane just points it at more things.
- **The product is an API.** Your platform team publishes `kind: WebApp`;
  consumers write 9 lines of YAML and get a compliant environment. No HCL,
  no credentials, no pipeline to babysit.

> **The one-sentence version for the camera:**
> *"Terraform automates the creation of infrastructure. Crossplane runs
> infrastructure the way Kubernetes runs pods: a control loop that never
> stops enforcing what you asked for."*

### Where each model wins (preview — full verdict in Section 17)

| | Pipeline (Terraform) | Control plane (Crossplane) |
|---|---|---|
| One-shot big builds | excellent | possible, awkward |
| Ongoing ops with drift protection | bolted-on (cron plan) | the entire design |
| Consumer experience | HCL + creds + CI | `kubectl apply` + RBAC |
| Maturity/ecosystem | 15+ years, huge registry | younger; cloud coverage patchy |

## 6. Concept Deep-Dive B — Crossplane's Building Blocks

*(Diagram + narration. Everything below appears live in Sections 7–16.)*

Four packages + two resource families. That's the whole vocabulary.

### Packages (things you *install*)

| Package kind | What it delivers | Example in this episode |
|---|---|---|
| `Provider` | CRDs for a *remote* API + the controller(s) to manage them + a ServiceAccount for the provider pods | `provider-kubernetes` → gives you `kind: Object` |
| `Function` | A container that runs one step of a composition pipeline | `function-patch-and-transform`, `function-auto-ready` |
| `Configuration` | A bundle: XRDs + Compositions + providers, installable in one shot | (not used in Ep 1 — Season 3) |

A package is "just an OCI image + a package manifest". When you `kubectl
apply` a `Provider`, the core package manager pulls the image, extracts the
CRDs out of it, creates the provider's Deployment and ServiceAccount, and
reports progress in the Provider's **status conditions** (`Installed`,
`Healthy`). You will watch all of this happen.

### Resources (things you *create*)

| Resource family | Managed by | What it is |
|---|---|---|
| **Managed resources (MRs)** | provider controllers | A *direct* mapping to one remote object. `Object` → one namespace/ConfigMap. `Bucket` → one S3 bucket. Terraform-resource equivalent. |
| **Composite resources (XRs)** | composition controller | An *abstraction*: one custom resource (WebApp) that composes many resources (namespace + deployment + service + configmap). Terraform has no equivalent — the closest is a module, but modules aren't APIs. |

### The vocabulary map (Terraform → Crossplane)

| Terraform | Crossplane | Difference that matters |
|---|---|---|
| provider block (credentials) | `ProviderConfig` | a resource in the API, swappable per-MR |
| resource block | managed resource (MR) | reconciled forever, not once |
| state file | the API server | already solved by etcd |
| module | XRD + Composition | module = files you call; XRD = an API you publish |
| `terraform plan` | `kubectl diff` / `crossplane render` | render works fully offline |
| `terraform apply` | `kubectl apply` | and then it *keeps applying*, continuously |
| `terraform destroy` | `kubectl delete` (respecting `removalPolicy`) | per-resource orphan vs delete choice |

---

## 7. Install Crossplane Core

Guided: `make crossplane-install` (then skip to Section 8 for the tour).

Manual:

```bash
# 1. Add the Helm repo (official charts)
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# 2. Install — pinned to the version in lab/versions.env
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace \
  --version "$(grep CROSSPLANE_CHART_VERSION lab/versions.env | cut -d'"' -f2)" \
  --wait --timeout 5m
```

What this did:

- Created the `crossplane-system` namespace
- Installed ~40 CRDs — the *Crossplane language itself*: `Provider`,
  `Function`, `ProviderConfig` (generic), plus the XRD/Composition machinery
- Started the `crossplane` controller Deployment (the package manager +
  core reconcilers) — on this lab it lands on the master with everything else

Check the version agreement (CLI major.minor should match):

```bash
crossplane version
kubectl get deployment -n crossplane-system crossplane -o \
  jsonpath='{.metadata.labels.app\.kubernetes\.io/version}'
```

> **On camera:** "One Helm release. Everything else in this episode —
> providers, functions, our platform API — arrives as *packages* through
> the package manager we just installed. Crossplane bootstraps itself."

## 8. What Just Got Installed — a Tour

```bash
kubectl get pods -n crossplane-system
# NAME                          READY   STATUS    AGE
# crossplane-5f8db7b4c4-x2k8p   1/1     Running  2m
# (crossplane-rbac-manager-...  1/1     Running  2m   <- if rbac.enabled)

# How much of the K8s API is now Crossplane?
kubectl get crd | grep -c crossplane

# The core object types — point at these one by one:
kubectl get providers        # none yet — next section
kubectl get functions        # none yet — Section 15
kubectl get providerconfig   # none yet — Section 10
```

> **On camera:** "Notice what ISN'T here: no state file, no CLI daemon, no
> database. Crossplane is controllers + CRDs — the same pattern as every
> operator you've ever installed. The novelty is only in what it points at."

## 9. Install a Provider (and what a provider actually IS)

Manual (mirrors what `make crossplane-install` does):

```bash
# a. Runtime config — fixes the provider's ServiceAccount name so our RBAC
#    binding has something predictable to point at
kubectl apply -f lab/providers/10-runtime-config.yaml

# b. RBAC — let the provider manage objects in this cluster
kubectl apply -f lab/providers/20-rbac.yaml

# c. The Provider itself — the package
kubectl apply -f lab/providers/00-provider.yaml
```

Now watch the package manager work — this is worth showing slowly:

```bash
kubectl get provider provider-kubernetes -w
# PACKAGE                          INSTALLED   HEALTHY   ...
# provider-kubernetes:v1.0.0       True        True

# While that goes Healthy, a Deployment appeared out of nowhere:
kubectl get deployments -n crossplane-system
# crossplane, provider-kubernetes-<hash>

# And new CRDs landed — the provider's product line:
kubectl get crd | grep kubernetes.crossplane.io
# objects.kubernetes.crossplane.io   (kind: Object)
# ...
```

What happened, step by step:

1. The `Provider` resource says "install package `xpkg.upbound.io/...`"
2. The core package manager **pulled the OCI image**, read its manifest
3. It **extracted the CRDs** inside the image and applied them — that's
   where `kind: Object` came from; *you* didn't write that CRD
4. It **created a Deployment** (the provider's controller) and a
   ServiceAccount (from our DeploymentRuntimeConfig)
5. It flipped the `Installed` and `Healthy` conditions you watched

> **On camera:** "A provider is three things in one: the schema for new
> resource kinds (CRDs), the controllers that manage them, and a
> runtime identity. Delivered as an OCI image. Terraform providers are
> binaries you invoke; Crossplane providers are containers that run forever."

**Why provider-kubernetes for episode 1?** No cloud account, no credentials
to rotate on camera, every viewer can run it — and the drift demo (Section
12) is pure Kubernetes, visible with tools you already know. The exact same
mental model then transfers to `provider-aws` in Season 5.

## 10. Credentials: ProviderConfig and InjectedIdentity

Before the provider can manage anything, it needs to know *as whom*. That's
the `ProviderConfig`:

```bash
kubectl apply -f lab/providers/30-provider-config.yaml
kubectl get providerconfigs.kubernetes.crossplane.io
# NAME      AGE
# default   3s
```

The file, in full (it's tiny — show it):

```yaml
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
```

What `InjectedIdentity` means: the provider pods use **their own
ServiceAccount** — the one we RBAC-bound in Section 9 — as their identity.
No secret, no token file, nothing to leak. In this lab, that ServiceAccount
can create anything in the cluster; on a real platform you'd scope the
ClusterRole down to exactly the kinds the provider should manage.

The alternatives (name them, don't demo them):

| `credentials.source` | Use when |
|---|---|
| `InjectedIdentity` | managing in-cluster resources (this episode) or with Workload Identity (EKS/GKE) |
| `Secret` | classic: cloud keys in a K8s Secret (Reference + key) |
| `Environment` | creds from the provider pod's env (IRSA-style) |
| `FileSystem` | mounted credential files |

> **On camera:** "Notice the shape: credentials are *resources in the API*,
> referenced by name from every managed resource. Rotate once, everything
> picks it up. Compare with Terraform: credentials live on the laptop of
> whoever runs apply."

## 11. Your First Managed Resources

Guided: `make demo-ep01` step 1. Manual:

```bash
kubectl apply -f episodes/01-getting-started/manifests/01-managed-resources.yaml
```

The manifest (read it on camera — every field is a teaching beat):

```yaml
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
metadata:
  name: demo-team-a-welcome
spec:
  providerConfigRef:
    name: default            # which credentials (Section 10)
  forProvider:
    manifest:                # the ACTUAL object — like a resource block body
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: welcome
        namespace: demo-team-a
      data:
        message: "Provisioned by Crossplane, not by a human"
```

Watch the provider take ownership:

```bash
kubectl get objects.kubernetes.crossplane.io
# NAME                 READY   SYNCED   AGE
# demo-team-a           True    True
# demo-team-a-welcome   True    True

# The real thing, proving Crossplane did it:
kubectl get ns demo-team-a
kubectl -n demo-team-a get configmap welcome -o yaml | head -20
```

**Anatomy — every managed resource in Crossplane looks like this:**

| Field | Meaning |
|---|---|
| `spec.forProvider` | desired state of the *remote* object — the resource block body |
| `spec.providerConfigRef` | which credentials to act as |
| `status.atProvider` | what the provider *observed* — Crossplane's `terraform show` |
| `status.conditions` | `Ready` (is it usable?), `Synced` (last reconcile succeeded?) |

**The two conditions you'll read forever:**

- **`Synced: True`** — the last reconcile loop succeeded (observed +
  updated). `False` = the provider errored; `kubectl describe` for the event.
- **`Ready: True`** — the resource is *usable* (an S3 bucket Ready ≠ created;
  it means endpoints resolve). Some MRs are Ready-but-not-yet-Synced and
  vice versa — always check both.

Show the ownership marks Crossplane left on the ConfigMap itself:

```bash
kubectl -n demo-team-a get configmap welcome -o yaml | grep -A6 metadata
# annotations/labels: crossplane.io/external-name, external-create-succeeded...
```

> **On camera:** "`forProvider` is the only thing I wrote. `atProvider` and
> the conditions are Crossplane writing back what it found. Spec goes down,
> status comes up — the oldest contract in Kubernetes."

## 12. The Reconcile Loop — Watch It Work (Drift Fight)

Theory first (30 seconds, then prove it):

- The provider doesn't watch *your apply* — it watches the **Object** in
  etcd, and periodically compares it against reality.
- The loop is **level-triggered**: "is actual == desired?" — it doesn't care
  *how* they diverged. Console click, colleague's kubectl, provider bug —
  same reaction: fix it.
- Frequency: the provider watches cluster events plus a periodic poll
  (~1 min worst case for provider-kubernetes).

The demo — do it by hand, it's better live:

```bash
# 1. Sabotage: delete the ConfigMap behind the control plane's back
kubectl -n demo-team-a delete configmap welcome

# 2. It's gone. Terraform would now be silent until the next plan.
kubectl -n demo-team-a get configmap welcome
# Error from server (NotFound)

# 3. Poll and watch the heal (usually < 60s)
while ! kubectl -n demo-team-a get configmap welcome &>/dev/null; do
  echo "healing..."; sleep 5
done
kubectl -n demo-team-a get configmap welcome
```

Now the sneakier drift — someone *edits* instead of deleting:

```bash
# 1. Hand-edit the ConfigMap's data
kubectl -n demo-team-a patch configmap welcome \
  -p '{"data":{"message":"edited by a human, defiantly"}}'

# 2. Wait for the next reconcile, then check:
kubectl -n demo-team-a get configmap welcome -o jsonpath='{.data.message}'
# ... back to "Provisioned by Crossplane, not by a human"

# 3. Show the evidence trail in the managed resource:
kubectl describe object demo-team-a-welcome | tail -20   # events: reconcile after update
```

**Delete the managed resource and the real one goes with it:**

```bash
kubectl delete object demo-team-a-welcome
kubectl -n demo-team-a get configmap welcome    # NotFound — cascade
```

> **On camera:** "Three attacks — delete, edit, delete-the-MR — three
> correct responses: recreate, revert, cascade-delete. That's a level-
> triggered control loop. Terraform's answer to all three is 'run plan and
> find out'."

## 13. Control the Lifecycle (updates, removalPolicy, orphan vs delete)

**Updates** propagate like everything else:

```bash
# Change desired state on the MR...
kubectl patch object demo-team-a --type merge \
  -p '{"spec":{"forProvider":{"manifest":{"metadata":{"labels":{"team":"a"}}}}}}'

# ...watch it appear on the real namespace
kubectl get ns demo-team-a --show-labels
```

**`removalPolicy`** decides what happens to the *real* object when the MR is
deleted:

```yaml
spec:
  removalPolicy: Delete   # default — delete the real object (what you saw in §12)
  # removalPolicy: Orphan — delete the MR, keep the real object
```

| Policy | When |
|---|---|
| `Delete` (default) | infra that belongs to the control plane — test namespaces, demo buckets |
| `Orphan` | adopting existing infra, migration periods, "break glass" resources |

Demo orphaning (fast, visual):

```bash
# Recreate the ConfigMap MR, but orphaning
kubectl apply -f - <<'EOF'
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
metadata:
  name: demo-team-a-welcome
spec:
  providerConfigRef: {name: default}
  removalPolicy: Orphan
  forProvider:
    manifest:
      apiVersion: v1
      kind: ConfigMap
      metadata: {name: welcome, namespace: demo-team-a}
      data: {message: "orphan me"}
EOF

kubectl delete object demo-team-a-welcome
kubectl -n demo-team-a get configmap welcome    # still there — orphaned
kubectl -n demo-team-a delete configmap welcome # clean up by hand
```

> **Note for v1 tutorial readers:** this was called `deletionPolicy` in
> Crossplane v1. See [Appendix A](#appendix-a--crossplane-v1-vs-v2-why-old-tutorials-mislead).

## 14. Publish Your Own API — the XRD

So far: Crossplane managing things one object at a time. Now the platform-
engineering move: **define a new API**.

Guided: covered by `make demo-ep01` step 3. Manual:

```bash
kubectl apply -f episodes/01-getting-started/manifests/02-xrd.yaml
kubectl get crd webapps.demo.crossplane.io
kubectl explain webapp --api-version=demo.crossplane.io/v1alpha1
# SPEC.SLUG, SPEC.REPLICAS, SPEC.IMAGE — the schema we authored
```

Read the XRD on camera; the teaching points:

- `group: demo.crossplane.io` — your own API group, like `apps` or `batch`.
  You are now a first-class API author, same as the Kubernetes steering committee.
- `names.kind: WebApp` — consumers write `kind: WebApp`.
- `scope: Namespaced` — **a v2 feature**: XRs live in namespaces, so teams
  can own, RBAC-scope, and quota them. (v1 XRs were cluster-scoped with
  "claims" in front — Appendix A.)
- `versions[].schema` — plain OpenAPI, exactly like any CRD. `slug` is
  required; `replicas` defaults to 2; `image` is optional (the Composition
  fills a default).

**The core Crossplane controller generated a real CRD from this** — show it:

```bash
kubectl get crd webapps.demo.crossplane.io -o yaml | head -40
```

> **On camera:** "Kubernetes just learned a new word. Nobody wrote a
> controller for WebApp yet — creating one right now would just sit there.
> That's the next piece."

## 15. The Composition — a Recipe Made of Functions

```bash
kubectl apply -f episodes/01-getting-started/manifests/03-composition.yaml

# And install the functions it uses (packages — same mechanism as §9):
kubectl apply -f lab/providers/40-functions.yaml
kubectl get functions -w
# function-patch-and-transform   INSTALLED/HEALTHY
# function-auto-ready            INSTALLED/HEALTHY
```

Anatomy of `webapp-standard` — walk it top to bottom on camera:

```yaml
spec:
  compositeTypeRef: {apiVersion: demo.crossplane.io/v1alpha1, kind: WebApp}
  mode: Pipeline           # v2: compositions ARE pipelines
  pipeline:
    - step: patch-and-transform
      functionRef: {name: function-patch-and-transform}
      input:               # everything this function needs, inline
        resources:         # 4 templates: namespace, deployment, service, configmap
          ...patches: FromCompositeFieldPath (spec.slug -> metadata.name, ...)
    - step: automatically-mark-ready
      functionRef: {name: function-auto-ready}
```

**How a pipeline runs** (this is the part every beginner misses — go slow):

1. A WebApp is created → the composition controller starts a **render**
2. The observed composite + connection details go **into** function 1
3. `patch-and-transform` returns a list of *desired composed resources*
   (it doesn't create anything!): namespace + deployment + service + configmap,
   each with fields patched in from `spec.slug`, `spec.replicas`, `spec.image`
4. Function 2 (`auto-ready`) looks at everything and decides when the XR
   can be marked `Ready`
5. The controller takes the rendered resources and creates/updates them —
   as plain Kubernetes objects (Namespace/Deployment/Service — no provider
   needed) — and updates their status back into the WebApp

**Offline rendering — the killer debugging feature** (use it live):

```bash
crossplane beta render episodes/01-getting-started/manifests/04-webapp.yaml \
                            episodes/01-getting-started/manifests/03-composition.yaml
# prints all 4 composed resources — no cluster required
```

> **On camera:** "This is `terraform plan` for compositions — except it's
> pure and offline: functions are containers, render runs them locally.
> You can unit-test your platform API in CI with no cluster at all."

**Why functions at all?** In v1, compositions had hardcoded patch-and-
transform logic. In v2 the pipeline is pluggable: `function-go-templating`
(write Helm-style templates), `function-kcl`, or your own container in
Go/Python. Season 2 lives here.

## 16. Use the API — Create, Trace, Update, Delete a WebApp

**Create — the payoff moment:**

```bash
cat episodes/01-getting-started/manifests/04-webapp.yaml
# 9 lines: kind, name, slug, replicas. That's ALL a developer writes.

kubectl apply -f episodes/01-getting-started/manifests/04-webapp.yaml
kubectl get webapp payments -w          # watch READY flip True
kubectl -n payments-team get all,cm     # the composed environment
```

**Trace — the dependency tree:**

```bash
crossplane beta trace webapp/payments
# WebApp payments — Ready
# └─ Namespace payments-team — Ready
# └─ Deployment webapp — Ready
# └─ Service webapp — Ready
# └─ ConfigMap webapp-config — Ready
```

**Update — change the spec, watch it flow through:**

```bash
kubectl patch webapp payments --type merge -p '{"spec":{"replicas":4}}'
watch kubectl -n payments-team get deployment webapp
# replicas scales 2 -> 4. The patch pipeline copied spec.replicas into the
# Deployment template, the composite controller updated the composed
# resource, and the (plain K8s) Deployment controller did the rolling update.
# A chain of control loops — point this out explicitly.

# Also: image comes from spec.image (or the Composition default):
kubectl patch webapp payments --type merge \
  -p '{"spec":{"image":"ghcr.io/stefanprodan/podinfo:6.7.0"}}'
```

**Consume it** (prove the environment actually works):

```bash
kubectl -n payments-team port-forward service/webapp 9898:9898 &
curl localhost:9898/ | head -1
```

**Delete — and the platform cleans up:**

```bash
kubectl delete webapp payments
kubectl get ns payments-team 2>&1        # NotFound — everything cascaded
```

> **On camera:** "Nine lines created four resources; one delete removed
> them. Now imagine `kind: Database` or `kind: Bucket` behind the same
> pattern — that's a platform."

## 17. Crossplane vs Terraform — the Full Comparison

*(Verdict segment. Table on screen; full narration in narration.md Phase 9.)*

| | Terraform | Crossplane |
|---|---|---|
| **Model** | CLI pipeline: plan → apply → exit | Control plane: controllers reconcile forever |
| **Source of truth** | state file (lock it, store it, back it up) | the API server (etcd) |
| **Drift** | detected at next plan (bolt on cron+CI) | corrected continuously (seconds–~1 min) |
| **Trigger** | human/CI runs a CLI | any apply to the API (kubectl, GitOps, UI) |
| **Language** | HCL | YAML + your OpenAPI schemas; `crossplane render` for plan |
| **Abstraction** | modules — files consumers call | XRD + Composition — APIs consumers create |
| **Credentials** | on the runner's machine/env | ProviderConfig resources, swappable, no copy on laptops |
| **Day-2 (update, scale, delete)** | rerun the pipeline | patch the resource |
| **Ecosystem** | 15+ yrs, ~1800 providers | younger; strong AWS/GCP/K8s; gaps elsewhere |
| **Weak spots** | state pain, drift blindness, HCL for consumers | v2 churn (Appendix A), patchy provider coverage, YAML verbosity at scale |

**The verdict (deliver honestly, both ways):**

- Choose **Terraform** when: one-shot/brownfield builds, org-wide HCL
  fluency, provider coverage you need doesn't exist for Crossplane.
- Choose **Crossplane** when: infra is a product for many teams, you want
  GitOps/kubectl as the only interface, continuous reconciliation matters,
  and you have a platform team to own the API.
- **They coexist beautifully:** Terraform builds the cluster (it built this
  lab's VMs — the callback), Crossplane runs what lives in and around it.
- **The litmus test:** "Who notices when someone changes infrastructure by
  hand at 2am?" If the answer is "the next time a human runs a pipeline" —
  you have a pipeline. If it's "a controller, within a minute" — you have
  a control plane.

## 18. Cleanup / Reset

Guided:

```bash
make cleanup-ep01          # episode workloads; Crossplane stays installed
make crossplane-uninstall  # removes Crossplane itself (lab untouched)
```

Manual (same as the script, in order):

```bash
kubectl delete -f episodes/01-getting-started/manifests/04-webapp.yaml --ignore-not-found
kubectl delete -f episodes/01-getting-started/manifests/01-managed-resources.yaml --ignore-not-found
kubectl delete namespace payments-team demo-team-a --ignore-not-found

# XRD + Composition are the "platform" — normally you keep them installed.
# To remove them too:
kubectl delete -f episodes/01-getting-started/manifests/03-composition.yaml --ignore-not-found
kubectl delete -f episodes/01-getting-started/manifests/02-xrd.yaml --ignore-not-found

# Full Crossplane removal:
kubectl delete -f lab/providers/30-provider-config.yaml --ignore-not-found
kubectl delete -f lab/providers/00-provider.yaml --ignore-not-found
kubectl delete -f lab/providers/40-functions.yaml --ignore-not-found
kubectl delete -f lab/providers/20-rbac.yaml --ignore-not-found
kubectl delete -f lab/providers/10-runtime-config.yaml --ignore-not-found
helm uninstall crossplane -n crossplane-system
kubectl delete namespace crossplane-system --ignore-not-found
```

> **Careful with namespace deletes:** deleting `crossplane-system` before
> the providers/MRs are gone can leave finalizers hanging (see
> Troubleshooting). The order above avoids that.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---|---|---|
| Provider stuck `Healthy=False` | `kubectl describe provider provider-kubernetes` → events | usually image pull from xpkg.upbound.io; wait or fix node egress |
| `Object` stuck `Synced=False` | `kubectl describe object <name>` → conditions + events | ProviderConfig name wrong (must be `default`); RBAC missing (`20-rbac.yaml`); SA name mismatch (apply `10-runtime-config.yaml` first) |
| WebApp never becomes `Ready` | `crossplane beta trace webapp/payments` | which composed resource is unhealthy? `kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-auto-ready` |
| Composition renders nothing | functions not Healthy: `kubectl get functions` | apply `lab/providers/40-functions.yaml`, wait for Health |
| `crossplane: command not found` | CLI missing | `brew install crossplane-cli` (demo.sh degrades, but trace/render need it) |
| Namespace delete hangs on finalizers | crossplane-system removed while MRs still existed | `kubectl patch <mr> -p '{"metadata":{"finalizers":[]}}' --type merge` (last resort) |
| Drift heal takes >2 min | provider relying on poll fallback | force reconcile: `kubectl -n crossplane-system delete pod -l pkg.crossplane.io/provider=provider-kubernetes` |
| Old-tutorial manifests rejected (`ClusterScope`, `claimNames`, `deletionPolicy`) | v1 syntax against v2 | see Appendix A — this series is v2-only |

## Appendix A — Crossplane v1 vs v2 (why old tutorials mislead)

Crossplane 2.0 (2025) restructured core concepts. If a blog post contradicts
this guide, check its date first.

| Concept | v1 (most tutorials) | v2 (this series) |
|---|---|---|
| Composite resource scope | cluster-scoped | **Namespaced** (or Cluster) — `scope: Namespaced` in the XRD |
| Claims | `claimNames` — the developer-facing copy of an XR | **removed** — namespaced XRs *are* the developer resource |
| Deletion policy | `deletionPolicy` | **`removalPolicy`** |
| Packages | `pkg.crossplane.io/v1` (beta) + `v1beta1` relics | `pkg.crossplane.io/v2` |
| Compositions | `mode: Resources` (built-in patching) + Pipeline | **Pipeline only** — patch logic lives in functions |
| MR finalizers | always on | opt-in — deletion works without finalizers by default |

## Appendix B — Glossary

| Term | One-liner |
|---|---|
| Crossplane | an add-on control plane for infrastructure, built from K8s CRDs + controllers |
| Package | an OCI image carrying CRDs + controllers (Provider), logic (Function), or a bundle (Configuration) |
| Provider | package that adds managed-resource kinds for one remote API |
| ProviderConfig | resource holding *how to authenticate* to the remote API |
| Managed resource (MR) | your desired remote object, reconciled continuously |
| XRD | your API definition (group/kind/schema) → generates a CRD |
| XR / composite resource | an instance of your API (e.g. `kind: WebApp`) |
| Composition | the recipe mapping an XR to composed resources, as a function pipeline |
| Composition function | a container doing one pipeline step (render desired resources) |
| `crossplane beta trace` | CLI tree of an XR and everything composed beneath it |
| `crossplane beta render` | offline composition render — the plan equivalent |
| Drift | actual ≠ desired; pipelines detect it late, control planes fix it |
