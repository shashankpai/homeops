# Episode 1 — Narration: Crossplane Getting Started

## A. Concepts (segment 2, ~6 min)

**The problem.** You have Kubernetes. You have infrastructure — cloud, databases, buckets, DNS. Terraform manages infra well, but the workflow is: human runs a CLI, reads a plan, applies, walks away. State lives in a file. Drift is found the *next* time someone runs plan. And your developers can't touch any of it without learning HCL and getting credentials.

**Crossplane's pitch.** What if infrastructure lived in the same control plane as your workloads? Crossplane extends Kubernetes with CRDs for infrastructure. Instead of a CLI that talks to clouds, you get controllers that run in the cluster and reconcile your infrastructure — forever, not once.

**The key difference — reconcile vs apply.**

> Terraform *automates the creation* of infrastructure. Crossplane *runs* the infrastructure, the same way your Deployment controller runs your pods.

Terraform: plan → apply → exit. If someone deletes the resource afterwards, nothing notices until the next plan. Crossplane: the moment the YAML hits the API server, a controller is watching. Delete the resource out-of-band? The controller sees "actual ≠ desired" and fixes it. That's the same control loop that restarts your pods — which is exactly what we covered in the control-loop Short.

**No state file.** Terraform's state file is its source of truth and its weak point: lock it, store it, back it up, never commit it. Crossplane's source of truth is the API server itself — the same etcd that already runs your cluster. `kubectl get` is your `terraform state list`.

**Abstraction done differently.** Terraform modules are files you call — the consumer still reads Terraform. Crossplane's XRDs are *APIs you publish* — a developer writes a 9-line `kind: WebApp` and never knows a Deployment, namespace, or provider config was involved. That's the platform-engineering promise.

**When to use which.**
- Big one-time builds, brownfield, existing HCL fluency → **Terraform**.
- Infra as a product for many teams, GitOps/`kubectl`-only interface, continuous reconciliation, self-service with guardrails → **Crossplane**.
- Both: Terraform builds the cluster (like our lab — Terraform provisioned these very VMs), Crossplane runs inside it.

**Honest cons** (credibility beat): Crossplane is younger, the provider ecosystem is smaller, cloud coverage is patchier than Terraform's, and v2 changed some core concepts (claims are gone, XRs are namespaced) — older tutorials will mislead you. This series targets v2.

## B. Demo beats (segments 3–7)

1. **What's installed** — "The core is one deployment. Everything else — providers, functions — is a package the package manager installs. Watch: `kubectl get providers` — that's not a pod, that's a *package definition*."
2. **First managed resource** — "This `Object` is a namespace defined Crossplane-style. `forProvider.manifest` is what the provider will create — like a Terraform resource block, but applied to the API server. Note the conditions: READY, SYNCED. Terraform prints those once; Crossplane *is* them."
3. **Drift** — "I'm going to do the thing every ops team fears: edit production by hand. `kubectl delete configmap`... and now we wait. The provider polls; in under a minute it'll notice the ConfigMap is gone and recreate it. Try doing that with Terraform without scheduling a pipeline."
4. **XRD** — "Now the real magic. I define a new API — `kind: WebApp` — with a schema. Crossplane creates a CRD for it. Kubernetes just learned a new word."
5. **Composition** — "This Composition is the recipe: when someone creates a WebApp, run these functions: patch-and-transform generates a namespace, deployment, service, configmap from the spec; auto-ready marks it Ready when they're all up."
6. **Payoff** — "Here's everything a developer writes: 9 lines. Apply... and there's the environment. Trace it: `crossplane beta trace` — that tree is composed resources. And when they delete the WebApp, the platform cleans up after them."
7. **Recap** — "Three things to take away: (1) infrastructure as CRDs, (2) controllers reconcile forever — drift dies, (3) XRD + Composition turn your platform into an API. Next episode: Compositions in depth — functions, versioning, and building a real internal platform. Subscribe."
