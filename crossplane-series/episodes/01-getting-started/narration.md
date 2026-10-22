# Crossplane Getting Started — Infrastructure as Kubernetes APIs
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for all phases.
> **Style:** Conversational, beginner-first — this is many viewers' *first*
> Crossplane exposure, so nothing is assumed. Every concept gets a plain-
> English explanation *and* a live command.
> **Pattern per phase:** CONCEPT → COMMAND → WHAT YOU SAW → WHAT IT MEANT.
> **Duration target:** ~40 minutes. Long is fine — this is the reference
> episode for the whole series.

---

## Phase 1 — Hook (0:00 – 1:30)

[0:00 — screen: two terminals side by side]

Watch this. Left terminal: I delete a ConfigMap in Kubernetes. With my hand. On purpose. On the right — nothing. No pipeline runs, no human gets paged, no cron job fires.

[0:20 — wait ~20s, right terminal]

...and it's back. Nobody ran anything. The cluster noticed, and the cluster fixed it.

[0:30]

That wasn't Kubernetes doing me a favor. That was Crossplane — a control plane for infrastructure that runs *inside* Kubernetes and reconciles what exists against what you asked for, forever. Terraform gives you that... only when someone runs plan and apply. Crossplane never sleeps.

[0:50]

In this episode we're going to start from zero: install Crossplane on a real cluster, understand every piece of it — providers, managed resources, provider configs, XRDs, compositions, functions — fight it, break it, and then use it to build our own platform API. And at the end I'll give you the honest verdict: Crossplane versus Terraform, when to use which, and when *not* to. Let's go.

---

## Phase 2 — The Problem (1:30 – 4:00)

[1:30 — diagram: the pipeline]

Here's the standard way we manage infrastructure. Terraform, or something like it. It's a pipeline: I write HCL, I run `terraform plan`, I review the plan, I run `terraform apply`, the state file gets updated, and... done. The pipeline exits.

[1:50]

And that "done" is the whole problem. Correctness ended when the apply ended. From this moment, nothing is watching. If someone clicks in the AWS console at 2am — the pipeline doesn't know. If a teammate hand-edits a resource — the pipeline doesn't know. You find out next time a human runs plan. And every team I've ever worked with ends up bolting on the same workaround: run `terraform plan` in CI every hour, alert if the exit code says "changes detected". Congratulations — you just reinvented drift detection as a cron job, with a state file as its single point of failure.

[2:30]

That state file. Let's be honest about what it is: a JSON database of what Terraform thinks exists, which is your real source of truth, which lives *outside* your infrastructure. You have to lock it, so two people don't apply at once. Store it in a backend, so it survives laptops. Back it up, so it survives the backend. And never, ever, commit it. It's infrastructure for your infrastructure.

[3:00]

And one more problem nobody puts on the slide: your *consumers*. A developer who needs a database doesn't want a database — they want their app to work. But with Terraform, to get that database they write HCL, they need cloud credentials in their pipeline, and they wait for someone's plan review. The platform is files. Not an API.

[3:30]

So let me show you the other model. And you already know it — because you use it every day.

---

## Phase 3 — The Control Plane Model (4:00 – 7:00)

[4:00 — diagram: kubectl apply → API → controllers → reconcile]

When you create a Deployment, you don't run a "deployment apply tool". You write YAML, you send it to the API server, and a controller watches it. If the pod dies, you don't re-run anything — the controller notices *state*: "what exists is not what was asked for" — and fixes it. That's a control loop. It's level-triggered: it reacts to how things *are*, not to events that happened.

[4:30]

Now — Crossplane's entire idea in one sentence: *point that same control loop at infrastructure.* Buckets, databases, DNS records, namespaces, whole cloud VPCs — defined as YAML in etcd, enforced by controllers that never stop.

[4:50 — diagram side by side: pipeline vs control plane]

Look at the differences:

- Desired state lives in the API server. No state file. `kubectl get` is your `terraform state list`. etcd already solved storage, watch, audit — Crossplane just reuses it.
- Correctness doesn't end. The loop runs forever. Delete the resource behind the controller's back, it gets recreated — you saw that in the cold open.
- The product is an API. Your platform team can publish `kind: WebApp`, and a developer gets a whole compliant environment from nine lines of YAML. No HCL, no credentials, no pipeline.

[5:40]

One sentence for it: **Terraform automates the *creation* of infrastructure. Crossplane *runs* infrastructure, the way Kubernetes runs pods.**

[5:50 — honesty beat]

Now, is this magic? No. It's operators. You've installed plenty — cert-manager, external-dns. Crossplane is one very large, very well-organized operator framework for *infrastructure*. If you understand deployments, you already understand half of Crossplane.

[6:10]

The other half is vocabulary, and it's small: providers, provider configs, managed resources, XRDs, compositions, functions. We're going to touch every single one in this episode, on a real cluster. By the end, none of those words will be scary.

[6:30]

The lab — you've seen it in the Kubernetes Under the Hood series: three-node K3s on Proxmox. Terraform built these VMs, which I promise becomes funny later. Prometheus and Grafana are running. We're just adding one more thing to it.

---

## Phase 4 — Install Crossplane (7:00 – 9:00)

[7:00 — terminal]

Crossplane installs as one Helm release. That's it:

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace --wait
```

[7:40 — while it runs]

What did we just get? Let me spoil it: Crossplane core is a *package manager* plus a bunch of CRDs. The CRDs are the language — Provider, ProviderConfig, XRD, Composition. The core controllers manage those. And that's genuinely all the "Crossplane" there is. Everything cloud-specific — AWS, GCP, Kubernetes itself — arrives later, as packages.

[8:10 — terminal]

```bash
kubectl get pods -n crossplane-system
kubectl get crd | grep -c crossplane
```

One pod — well, two with the RBAC manager. And look at this: forty-plus CRDs, from one chart. This is Crossplane's language definition. Every provider and function we install today gets installed *by* this thing — Crossplane bootstraps itself.

[8:45]

Versions note: we're on v2 — I'll flag where v1 differs as we go, because most tutorials out there are v1 and they will lie to you. Claims are gone, XRDs are namespaced, deletion policy got renamed. Cheat sheet is in the repo notes.

---

## Phase 5 — Providers: What They Actually Are (9:00 – 13:00)

[9:00]

A provider is the thing that teaches Crossplane a new API. And here's the mental model I want you to keep: **a provider is three things in one package.**

One: the schema — CRDs for the resource kinds it manages. Two: the controllers that watch those resources and talk to the remote API. Three: a runtime identity — service accounts, pods — for those controllers to run as. And the package is just an OCI image. Terraform providers are binaries you *invoke*. Crossplane providers are containers that *run forever*.

[9:40]

For episode one we're using `provider-kubernetes` — the provider whose "cloud" is this cluster itself. Perfect teaching provider: no cloud account, no credentials, and everything it does is visible with kubectl. The exact same mental model transfers to provider-aws later.

[10:00 — terminal; the manifest is on screen]

```bash
kubectl apply -f lab/providers/10-runtime-config.yaml
kubectl apply -f lab/providers/20-rbac.yaml
kubectl apply -f lab/providers/00-provider.yaml
kubectl get provider provider-kubernetes -w
```

[10:20 — while watching]

Watch this closely, because this is the package manager working. The Provider resource just says "install this image". The core controller pulls it from the registry, reads the package manifest, extracts the CRDs out of the image... and now look:

[10:50]

```bash
kubectl get crd | grep kubernetes.crossplane.io
kubectl get deployments -n crossplane-system
```

A `kind: Object` CRD appeared. I didn't write that CRD — the *package* contained it. And a new Deployment appeared — the provider's controller pods. With a service account, whose name we pinned with the runtime config, and whose permissions we granted with one ClusterRoleBinding. That RBAC decision is real platform engineering, by the way: the provider can only do what its service account can do. Scope that role tightly in production.

[11:40]

Two conditions on the Provider: **Installed** — the image pulled and CRDs applied. **Healthy** — the controllers are up and serving. Both True, we're in business.

[12:00]

Quick recap of the vocabulary so far: Provider — a package of CRDs + controllers + identity. Installed with `kubectl apply`. Delivered as an OCI image. Watched by the core package manager. That's the install story for *everything* in Crossplane — including the composition functions we'll meet later.

---

## Phase 6 — ProviderConfig: Credentials Without Secrets (13:00 – 15:00)

[13:00]

One question left before the provider can act: *as whom?* When it talks to the API that it manages — this cluster, in our case — what identity does it use? That's what a ProviderConfig answers.

[13:20 — terminal; show the whole file, it's tiny]

```yaml
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
```

`InjectedIdentity`: the provider pods use their own ServiceAccount — the one we RBAC-bound a minute ago. No secret, no token, nothing to leak or rotate on camera.

[13:50]

For a cloud provider you'd use a Secret reference instead — cloud keys stored as a Kubernetes Secret, referenced *by name*. And notice the shape of that: credentials become **resources in the API**. Every managed resource points at its ProviderConfig. Rotate the credential once, everything using that config picks it up. Compare that to Terraform, where credentials live... on the laptop of whoever runs apply.

[14:30]

```bash
kubectl apply -f lab/providers/30-provider-config.yaml
kubectl get providerconfigs.kubernetes.crossplane.io
```

Provider installed, identity configured. Time to actually manage something.

---

## Phase 7 — Managed Resources: Your First One (15:00 – 19:00)

[15:00]

Here's a namespace. As Crossplane sees it:

```yaml
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
spec:
  providerConfigRef: {name: default}
  forProvider:
    manifest:
      apiVersion: v1
      kind: Namespace
      metadata: {name: demo-team-a}
```

Read the anatomy with me — because **every managed resource in Crossplane, for every provider, for every cloud, looks like this**.

`kind: Object` — that's the provider's product: any Kubernetes object as a managed resource. `providerConfigRef` — which identity to act as, from the last section. And `forProvider` — the *actual thing you want*, the body of what would be a Terraform resource block. Everything Crossplane-specific is scaffolding around your desire.

[15:50 — terminal]

```bash
kubectl apply -f episodes/01-getting-started/manifests/01-managed-resources.yaml
kubectl get objects.kubernetes.crossplane.io
```

```
NAME                 READY   SYNCED
demo-team-a          True    True
demo-team-a-welcome  True    True
```

[16:20]

Two conditions, and you will read these two words for the rest of your Crossplane life:

- **Synced** — did the last reconcile loop succeed? I observed the world, I updated what needed updating, no errors. False means the provider hit a problem — describe it.
- **Ready** — is the resource *usable*? For a ConfigMap that's basically "it exists"; for a database it means "created *and* endpoints resolve". Always check both.

[16:50]

Now the part I want you to internalize: spec goes down, status comes up. Everything I wrote is in `forProvider` — my desire. Crossplane writes back in `atProvider` — what it observed — and in those conditions. The API server is the source of truth, spec is what I want, status is what there is. The oldest contract in Kubernetes, applied to infrastructure.

[17:20 — terminal]

```bash
kubectl get ns demo-team-a
kubectl -n demo-team-a get configmap welcome -o yaml
```

And there it is. A namespace and a ConfigMap, created by a controller, from desired state in etcd. Terraform users, notice what didn't happen: no plan output, no apply, no state file, no locking. `kubectl get` *is* `terraform state list` — it's all right here.

[18:20]

And one more thing that will matter in a minute — look at the annotations on that ConfigMap: Crossplane marked it with external-name and create timestamps. The provider tracks ownership so it knows this ConfigMap is *its* ConfigMap. Just like a Deployment owner-references its ReplicaSets. Ownership in the API, not in a state file.

---

## Phase 8 — The Drift Fight (19:00 – 23:30)

[19:00]

Now the segment this whole episode exists for. I'm going to do the thing every ops team fears: hand-edit production. Watch.

[19:10 — terminal]

```bash
kubectl -n demo-team-a delete configmap welcome
kubectl -n demo-team-a get configmap welcome   # NotFound
```

Gone. Now — in Terraform-world, this is the part where nothing happens until the next pipeline run. In Crossplane-world, the provider is watching that managed resource, and it polls and watches actual state. "What exists is not what was asked for." A level-triggered controller doesn't care *how* it diverged. Console click, defiant colleague, cosmic ray — same answer: fix it.

[19:50 — poll loop]

```bash
while ! kubectl -n demo-team-a get configmap welcome &>/dev/null; do
  echo healing...; sleep 5
done
```

[20:30 — healed]

And it's back. Usually under a minute. I fought the control plane, and the control plane won.

[20:45]

Deletion was attack one. Attack two — someone doesn't delete, they *edit*:

```bash
kubectl -n demo-team-a patch configmap welcome \
  -p '{"data":{"message":"edited by a human, defiantly"}}'
```

Sneakier — the object exists, `kubectl get` looks fine, but the data is wrong. Drift that pipelines are *specifically* blind to, because the object still exists. Give it a reconcile cycle... and the message is back to what the managed resource says. The provider overwrote the edit.

[21:40]

Attack three — flip it around. What happens if I delete the *managed resource*, not the object?

```bash
kubectl delete object demo-team-a-welcome
kubectl -n demo-team-a get configmap welcome   # NotFound!
```

Cascade delete. The MR owned that ConfigMap, so when I remove the MR, the provider removes the thing. `terraform destroy` — but per-resource, instantly, no plan review screen.

[22:20]

Recap the three attacks and the three correct responses: delete → recreate; edit → revert; delete-the-MR → cascade. That's a control loop doing level-triggered reconciliation. And here's the kicker for the Terraform comparison: Terraform's response to all three is the same — "run plan and find out."

[23:00]

Hold on though — "Crossplane deletes my infrastructure when I delete a YAML object" is also how you *lose* infrastructure by accident. Crossplane thought about that: `removalPolicy`. Default is Delete — what you just saw. But I can set `Orphan`: delete the managed resource, and the real object stays behind, unmanaged. That's how you *adopt* existing infrastructure — you manage it, learn from it, and if you ever want to stop managing it, you walk away without destroying anything. We'll flip that flag live in a second. First — let's build the API.

---

## Phase 9 — XRDs: Publish Your Own Kind (23:30 – 26:30)

[23:30]

Everything so far: Crossplane managing things, one object at a time. It's neat, but honestly Terraform does that too. *This* is the segment Terraform cannot follow.

[23:45]

Watch this file. It's a CompositeResourceDefinition — an XRD:

```yaml
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: webapps.demo.crossplane.io
spec:
  group: demo.crossplane.io
  names: {kind: WebApp, plural: webapps}
  scope: Namespaced
  versions:
    - name: v1alpha1
      schema:
        openAPIV3Schema:
          spec: {slug, replicas, image}
```

[24:20]

Read what this is: I am defining an API group — `demo.crossplane.io`, my group, next to `apps` and `batch` — with a kind called WebApp, namespaced so teams can own and RBAC-scope them, with a schema: required `slug`, optional `replicas` defaulting to 2, optional `image`. Plain OpenAPI, exactly like any CRD you've written.

[24:50 — terminal]

```bash
kubectl apply -f episodes/01-getting-started/manifests/02-xrd.yaml
kubectl get crd webapps.demo.crossplane.io
kubectl explain webapp
```

Kubernetes just learned a new word. `kubectl explain` teaches it back to me. If I create a WebApp right now, it gets stored... and then sits there forever, because nothing *handles* it yet. There's no controller for "webapp". Interesting state, isn't it? The API exists; the meaning doesn't. Let's give it meaning.

[25:50]

Meaning in Crossplane comes from a Composition. And the reason I slowed down on the XRD is this contrast: with Terraform, if I wrap complexity in a module — the consumer still reads and writes Terraform. Here, the consumer *only ever sees the API*. `kind: WebApp`, three fields, full stop. The complexity lives behind it, in the composition — and that's what a platform *is*. An API with opinions behind it.

---

## Phase 10 — Compositions and Functions (26:30 – 31:00)

[26:30]

The composition is the recipe: when someone creates a WebApp, here's everything they get and how it's built. Ours composes four resources: a namespace, a deployment, a service, and a configmap — a tiny compliant environment for a team's web app.

[26:50]

But first — v2 changed how compositions work, and it's a change for the better. In v1, a composition had built-in patching logic and you'd have these enormous YAML files full of patch rules. In v2, a composition is a **pipeline of functions**. Look at the shape:

```yaml
mode: Pipeline
pipeline:
  - step: patch-and-transform
    functionRef: {name: function-patch-and-transform}
    input:
      resources: [namespace, deployment, service, configmap...]
  - step: automatically-mark-ready
    functionRef: {name: function-auto-ready}
```

[27:30]

And here's the mental model everyone misses, so let me be really precise. Functions do not create anything. When a WebApp appears, the composition controller starts a **render**: it takes the WebApp — what the user asked for — and passes it into function one. Function one is `patch-and-transform`, a container that takes templates plus patches and returns a list of *desired* resources: "here's the namespace, named from spec.slug; here's the deployment, replicas from spec.replicas, image from spec.image or the default; here's the service; here's the configmap." It returns *paperwork*. Then function two, `auto-ready`, looks at the rendered resources and decides when the WebApp can be called Ready. Then — and only then — the composition controller actually creates and updates those resources and streams their status back into the WebApp. Functions render. Controllers create.

[28:40]

Why is this good? Because the pipeline is pluggable. Don't like patch-and-transform's YAML? Swap in `function-go-templating` and write Helm-style templates. Or KCL. Or write your own function in Python or Go — it's just a container. That's a whole season of this series, and it starts from this exact lab.

[29:10 — terminal]

```bash
kubectl apply -f lab/providers/40-functions.yaml
kubectl get functions -w      # INSTALLED/HEALTHY — same package flow as the provider
kubectl apply -f episodes/01-getting-started/manifests/03-composition.yaml
```

Same install story — functions are packages too, pulled as OCI images, installed by the same package manager. Consistency is a feature.

[29:50 — the killer feature]

Now let me show you something Terraform genuinely cannot do. I can render this composition *completely offline*:

```bash
crossplane beta render manifests/04-webapp.yaml manifests/03-composition.yaml
```

All four resources, printed, exactly as they'd be created — and no cluster was involved. Functions are containers; the render runs them locally. This is `terraform plan` — pure, offline, no state file — and you can run it in CI on every PR to your platform definition. You can *unit-test your platform*.

[30:50]

XRD defines the API. Composition gives it meaning. Now let's use it.

---

## Phase 11 — The Payoff: A WebApp (31:00 – 36:00)

[31:00 — the whole file on screen; let it breathe]

This is everything a developer writes:

```yaml
apiVersion: demo.crossplane.io/v1alpha1
kind: WebApp
metadata: {name: payments, namespace: default}
spec:
  slug: payments-team
  replicas: 2
```

Nine lines. Nine. No namespace YAML, no deployment YAML, no service YAML, no configmap YAML, no copying the "standard deployment" from the last team's repo. They ask for an app; the platform does the rest.

[31:40 — terminal]

```bash
kubectl apply -f episodes/01-getting-started/manifests/04-webapp.yaml
kubectl get webapp payments -w
```

Watch the status go Ready — that's auto-ready doing its job, checking all four composed resources. And:

[32:10]

```bash
kubectl -n payments-team get all,cm
```

There it is. The namespace, the deployment — podinfo, running, two replicas — the service, the configmap. One resource in, an environment out. And the status flowed back the other way: the WebApp's conditions summarize everything composed beneath it. You can build dashboards off *that*.

[32:50 — the tree]

Now the tool that will follow you around forever:

```bash
crossplane beta trace webapp/payments
```

```
WebApp payments — Ready
├─ Namespace payments-team
├─ Deployment webapp
├─ Service webapp
└─ ConfigMap webapp-config
```

The full dependency tree, live. When something's wrong, you don't guess — you trace, you find which composed resource is unhappy, you look at *its* events. Incident response for infrastructure, the kubectl way.

[33:30 — updates: the chain of loops]

Now updates — this is where it gets philosophically beautiful. Watch what happens when I change the spec:

```bash
kubectl patch webapp payments --type merge -p '{"spec":{"replicas":4}}'
watch kubectl -n payments-team get deployment webapp
```

Four replicas. But think about the chain that just fired: I patched the WebApp — the composition controller re-renders — patch-and-transform copies spec.replicas into the deployment template — the controller updates the composed Deployment — and the *plain Kubernetes* Deployment controller does the rolling update. A chain of control loops, each doing one job, composing into platform behavior. Nobody restarted anything. No pipeline ran. `kubectl patch` to scale an environment.

[34:50 — prove it works]

And it's real infrastructure, so let's use it:

```bash
kubectl -n payments-team port-forward service/webapp 9898:9898 &
curl localhost:9898/
```

[35:20 — delete]

And the final power move — cleanup:

```bash
kubectl delete webapp payments
kubectl get ns payments-team      # NotFound
```

Delete the claim on the API, the platform deletes everything it composed. Nine lines in, one line out, environment completely cleaned. Imagine `kind: Database` behind this pattern. That's a platform.

---

## Phase 12 — The Honest Verdict: Crossplane vs Terraform (36:00 – 40:00)

[36:00 — table on screen]

Time to pay off the promise from the intro. The full, honest comparison.

**Model.** Terraform is a pipeline — plan, apply, exit. Crossplane is a control plane — controllers that reconcile forever. This difference drives *everything* downstream.

**State.** Terraform has a state file: lock it, store it, back it up, never commit it. Crossplane has no state file — the API server is the state, and etcd already solved that problem years ago.

**Drift.** Terraform detects drift when a human or CI runs plan — bolt on a cron. Crossplane *corrects* drift continuously. You watched it. That was the cold open.

**Abstraction.** Terraform modules: consumers still write HCL, still hold credentials, still wait on pipelines. Crossplane XRDs: consumers write nine lines of `kind: WebApp`. Modules are files you call; XRDs are APIs you publish.

**Updates and day-2.** Re-run the pipeline, versus... patch the resource. And GitOps fits for free: Argo CD syncing Crossplane resources is just Argo CD doing what it already does.

[37:40 — and now the case FOR Terraform]

But this table has two columns, and I promised honesty. Terraform is fifteen years old, with providers for nearly everything on Earth. Crossplane's provider ecosystem is younger, and cloud coverage is real but patchier. If your infra is a one-shot, brownfield, or your org already breathes HCL — Terraform is the *correct* answer, and v2 churn means old Crossplane tutorials will actively mislead you today. It's a younger technology and you should price that in.

[38:30 — the litmus test]

So here's the litmus test I use. Ask: *"Who notices when someone changes infrastructure by hand at 2am?"* If the answer is "the next time a human runs a pipeline" — you have a pipeline, and you should know that's what you have. If the answer is "a controller, within a minute" — you have a control plane.

- One-shot builds, brownfield, HCL-fluent org → **Terraform**.
- Infra as a product for many teams, kubectl-and-GitOps as the interface, drift matters → **Crossplane**.
- And in practice: both. Terraform builds the cluster. Crossplane runs inside it. This lab? Terraform built these very VMs, and Crossplane just ran on top of them. No irony wasted.

[39:40 — wrap]

Everything you saw today is in the repo: the install, the provider, the XRD, the composition, every command from this episode in a runnable lab guide — go break it, that's what it's for. Next episode: compositions in depth — real functions, dependencies between resources, versioning your platform API like a product. Subscribe, and I'll see you in the control plane.
