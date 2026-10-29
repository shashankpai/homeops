# Crossplane Getting Started — Infrastructure as Kubernetes APIs
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for all phases.
> **Style:** Conversational, beginner-first — this is many viewers' *first*
> Crossplane exposure, so nothing is assumed. Every concept gets a plain-
> English explanation *and* a live command.
> **Pattern per phase:** CONCEPT → COMMAND → WHAT YOU SAW → WHAT IT MEANT.
> **Duration target:** ~45 minutes. Long is fine — this is the reference
> episode for the whole series. Phases 5–7 are the conceptual core —
> providers, identity, and managed resources — and are paced slowly on
> purpose: everything else in the series stands on them.

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

## Phase 5 — Providers: Teaching the Control Plane a New Language (9:00 – 14:00)

[9:00]

Here's a question nobody asks early enough, and it's the key to everything: after we installed Crossplane core... what can it actually *do*?

The honest answer: almost nothing. And *by design*. Crossplane core has no idea what an S3 bucket is. It has never heard of Route 53. It doesn't even know what a namespace is — and it's *running inside Kubernetes*. The core knows exactly two jobs: how to *install and run packages*, and how to *watch resources and run their controllers*. Everything cloud-specific, everything useful, arrives later.

[9:30 — analogy]

Think of it like a phone out of the box. The operating system is Crossplane core: it manages apps, runs them, updates them, kills them if they misbehave — but it ships without a single app. The app store? That's the Crossplane package ecosystem. And "apps" are called **providers**.

[9:50]

So when someone says "Crossplane can manage AWS" — that's imprecise, and the imprecision matters. *Crossplane* can't manage AWS. A **provider** — a package you install into Crossplane — can manage AWS. provider-aws, provider-gcp, provider-sql, provider-kubernetes... each one teaches the same control plane one new language.

[10:10 — the three things]

And here's what I need you to remember, because it's the anatomy of every provider you will ever install. A provider is **three things, delivered as one OCI image**:

**One — the vocabulary.** CRDs that define new resource kinds. Schema, fields, validation. When provider-kubernetes installs, your cluster learns a new word: `kind: Object`. When provider-aws installs, it learns *hundreds*: `Bucket`, `IAMRole`, `VPC`...

**Two — the workers.** The controllers for those kinds. A CRD without a controller is a suggestion — a schema nobody reads. The controllers are what watch your resources and go do the work.

**Three — the identity.** A runtime: pods, service accounts — *who* those workers run as when they talk to the remote API.

Vocabulary, workers, identity. Same image. Keep that shape in your head; we're about to watch all three parts appear live.

[11:00 — terminal]

For this episode we're using `provider-kubernetes` — the provider whose "cloud" is this cluster itself. Why start here? Three reasons. No cloud account — you can follow along with just kind or k3s. No credentials — nothing to rotate, nothing to redact on screen. And everything it does is visible with kubectl — you can *see* every move it makes. The mental model we build here transfers unchanged to provider-aws later. It's training wheels that never need to come off.

[11:30 — terminal; manifest on screen]

Three small files, in this order, and the order matters:

```bash
kubectl apply -f lab/providers/10-runtime-config.yaml   # pins the provider's SA name
kubectl apply -f lab/providers/20-rbac.yaml             # grants that SA its powers
kubectl apply -f lab/providers/00-provider.yaml          # the package itself
```

[11:50]

Files one and two are the *identity* part — we're doing it first so the provider's workers never exist without their permissions already in place. That's not a demo trick, that's how you should do it in production too: never let a provider boot into more privilege than you planned for it.

[12:10 — watch it]

Now watch the package manager work. This is my favorite part of the whole episode:

```bash
kubectl get provider provider-kubernetes -w
```

```
PACKAGE                       INSTALLED   HEALTHY
provider-kubernetes:v1.0.0
provider-kubernetes:v1.0.0   True
provider-kubernetes:v1.0.0   True        True
```

Two conditions, flipping live, and each one has a precise meaning.

**Installed** — the package manager pulled the OCI image from the registry, read its manifest, extracted the CRDs, applied them, and started the provider's runtime. The *app* finished installing.

**Healthy** — the controllers are up, connected to the API, and serving. The app isn't just installed, it's *running well*.

Two words, two different failure modes. If Installed never goes True — that's usually a registry or network problem. If Installed is True but Healthy won't come — the controllers are crashing or can't authenticate. Watch *which* word is stuck, and you already know where to look. That's half of Crossplane debugging, right there.

[13:10 — the CRDs appear]

Now the payoff. While that went Healthy, three things materialized that I never wrote. Let me show you:

```bash
kubectl get crd | grep kubernetes.crossplane.io
kubectl explain object
kubectl get deployments -n crossplane-system
```

A new CRD — `kind: Object`. And it's *documented*: `kubectl explain` works, because the schema shipped *inside the package*. I want to flag this, because it's the moment most people go "wait, what?" — **the CRDs came out of the package image.** You didn't define a resource kind for namespaces-as-code; the provider *brought it with it*. Your cluster's API just grew, on demand, from an image pull. That's what "provider" means: install it, and new infrastructure kinds simply exist.

And second: a new Deployment — the provider's controller pods, running in crossplane-system, with a service account whose name we pinned and whose powers we granted. The *workers* part of our anatomy. From now on, for the rest of this series, there is a little controller in this cluster whose entire purpose in life is to watch `Object` resources and make reality match them.

[13:50 — the contrast, and a caution]

So compare the two worlds. A Terraform provider is a *binary* — inert until a human invokes it, running with whatever credentials happen to be on that machine. A Crossplane provider is a *resident* — always on, using exactly the identity you gave it, scoped by RBAC you control. And that last point is real security engineering, not ceremony: the provider can only do what its service account allows. In production, don't do what we're doing today with a broad role — grant it only the kinds it manages. Least privilege, applied to your infrastructure control plane.

[14:00 — recap]

Recap, because this carries everything: a provider is vocabulary, workers, and identity in one image, installed by the package manager we booted in Phase 4, reporting its life story in two conditions — Installed and Healthy. But it's standing there with its hands in its pockets, because we haven't answered one question: *as whom* does it act? Let's give it an identity.

---

## Phase 6 — ProviderConfig: Identity Without Secrets (14:00 – 17:00)

[14:00]

Every API asks the same first question: *who's asking?* Your cluster asks it constantly — every single kubectl command you've ever run was authenticated and authorized. So when our provider goes to manage objects in this cluster, guess what: it gets carded too. It needs an identity. That's what a ProviderConfig is — not credentials *in* Crossplane, but the answer to *which identity do my workers use, for this remote API*.

[14:30 — the file, on screen; it's tiny on purpose]

```yaml
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
```

One word is doing all the work: `InjectedIdentity`. It means: **the provider pods use their own ServiceAccount as their identity.** No token file, no secret, no environment variable. When the provider talks to the API server, it presents the service account token that Kubernetes automatically mounts into every pod — the same identity we pinned in the runtime config and scoped with RBAC in the last phase. The pieces are all connected: the SA we named, the role we bound, and now the config that says *use it*.

[15:20]

Why is this elegant? For in-cluster management, the identity needed *already exists* — creating a secret to hold it would be redundant and just one more thing to leak. And here's the part that scales beyond this episode: on EKS or GKE, this *same source* can stand in front of cloud APIs too, through Workload Identity — where the platform maps that service account to a cloud role. One pattern, zero long-lived credentials, all the way up.

[15:50 — the alternatives, and when]

For the cases where you do need real credentials, look at the other sources, because you'll meet them in the wild:

- **Secret** — the classic: cloud keys stored as a Kubernetes Secret; the config references it by name. This is what you'd use with provider-aws in most clusters today.
- **Environment** — credentials handed to the provider pod as environment variables, IRSA-style.
- **FileSystem** — mounted credential files.

Don't memorize them. Memorize the *shape*: in every case, the credential is referenced, never inlined. Identity becomes a **resource in the API**, addressed by name.

[16:20 — why "resources in the API" is a design win]

And that shape buys you three things Terraform can't:

**One — separation of powers.** The person who creates the ProviderConfig is not necessarily the person who creates managed resources. Platform team holds the credentials; app teams never see them.

**Two — swapping.** Need a different set of credentials for a sandbox versus prod? Two ProviderConfigs. Each managed resource points at the one it wants — `providerConfigRef: name: prod-credentials` — and you can retarget a workload by editing one line.

**Three — rotation.** Rotate the underlying Secret *once*, and every resource using that config picks it up on the next reconcile. Compare that with the Terraform world, where credentials live on whatever machine happens to run apply — and yes, the name `default` matters too: if a managed resource doesn't name a config explicitly, the provider looks for one called `default`. That's why ours is named that.

[17:00]

Identity solved, with zero secrets on screen. The provider is installed, healthy, and it knows who it is. Time to finally manage something — and I mean *really* look at how it's expressed, because this next YAML is the shape of everything to come.

---

## Phase 7 — Managed Resources: The Atom of Crossplane (17:00 – 23:00)

[17:00]

Everything in Crossplane, no matter how sophisticated the abstraction, eventually bottoms out in the thing we're about to create. A **managed resource**. The atom.

Definition, in one sentence: *a managed resource is one piece of real-world infrastructure, expressed as a Kubernetes resource, and kept correct by a provider's controller.* One row in your infrastructure — as a YAML object in etcd.

[17:30 — the manifest, full screen; take your time]

Here's one. A namespace — but as Crossplane sees it:

```yaml
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
metadata:
  name: demo-team-a
spec:
  providerConfigRef:
    name: default
  forProvider:
    manifest:
      apiVersion: v1
      kind: Namespace
      metadata:
        name: demo-team-a
```

Let me walk every line, because **every managed resource in every provider for every cloud on Earth has this exact anatomy.** Learn it once, here, and you can read provider-aws YAML next month without blinking.

[18:00 — field by field]

`kind: Object` — the kind our provider installed in the last phase. provider-kubernetes's entire product line is one generic kind: "any Kubernetes object". Other providers have rich kind libraries — `Bucket`, `Cluster`, `ReplicationGroup`.

`spec.providerConfigRef: name: default` — *who do I act as?* Straight back to the last phase. This is the pointer that connects a piece of infrastructure to its identity — and notice it's a pointer, not the credential itself. Change this one line, and this namespace gets managed under a different identity.

And now the big one: `spec.forProvider`. **Everything I actually want, lives here.** Read what's inside — apiVersion, kind, metadata — that's not "YAML inspired by Kubernetes". That *is* Kubernetes YAML. The entire object I want to exist is embedded, verbatim, under `forProvider.manifest`. Same for a cloud resource: the `forProvider` block of an S3 bucket holds region, versioning, encryption — the API's own fields, namespaced under one wrapper. The wrapper is Crossplane's; the content is the remote API's.

That's a quietly powerful design choice: **you're not learning a new language for each cloud.** The knowledge you already have of each API transfers inside `forProvider`; Crossplane only ever asks you to learn the wrapper. Terraform asks you to learn HCL *and* its resource model *and* the cloud's semantics. Crossplane asks for the semantics only.

[19:40 — apply, watch]

```bash
kubectl apply -f episodes/01-getting-started/manifests/01-managed-resources.yaml
kubectl get objects.kubernetes.crossplane.io -w
```

```
NAME                 READY   SYNCED
demo-team-a          True    True
```

Two words appeared. You will read these two words for the rest of your Crossplane life, so let's get them *precise*, because they answer different questions:

**`Synced`** answers: *did the controller's last loop complete cleanly?* It went out, observed the world, compared it to my spec, fixed what needed fixing — no errors. `Synced: False` means the *control plane* has a problem — usually credentials or permissions. The controller itself is telling you it couldn't do its job.

**`Ready`** answers: *is the actual thing usable, right now?* For a ConfigMap, "usable" is trivially "it exists" — so Ready and Synced move together. But for a database, created and Ready are *very* different: created means the DB exists; Ready means it exists *and* the endpoint resolves and you can connect.

The way I keep them straight: **Synced is about the messenger, Ready is about the package.** Synced means "your controller finished its errand without tripping." Ready means "the thing it went to get is actually in your hands." A database can be Synced and not Ready — ordered fine, still baking. It can even be Ready and not Synced — the database works, but the *last* observation failed. Two words, two axes. Check both, always.

[21:10 — spec down, status up]

Now the contract underneath, and it's the oldest one in Kubernetes: **spec goes down, status comes up.** Everything I wrote was `forProvider` — my desire, handed to the API server. And everything the provider learned, it writes back in two other places: `status.atProvider` — what it *observed*, the real object as it actually is, your `terraform show` equivalent — and those two conditions. Desired state, down. Observed state, up. The gap between them is the controller's entire to-do list, every minute of every day.

[21:40 — the real thing]

Proof time:

```bash
kubectl get ns demo-team-a
kubectl -n demo-team-a get configmap welcome -o yaml | grep -A6 metadata
```

There it is — a namespace, created by a controller. And look at the annotations on the ConfigMap: `crossplane.io/external-name`, creation timestamps, ownership marks. The provider *signed its work*, exactly the way a Deployment owner-references its ReplicaSets. Which means there is no state file holding "I created this": the ownership lives in the API, on the object, where anything can read it. `kubectl get` — what you just did — *is* `terraform state list`. All of it. Forever.

[22:30 — the flip]

And here's the mental flip that separates people who *get* Crossplane from people who use it. Before today, you probably thought of the real object — the namespace, the database — as the *real* thing, and any record of it as a shadow. Managed resources reverse that: **the managed resource in the API is the source of truth; the real object is the shadow.** The cloud object, the namespace, the ConfigMap — they're just the *current output* of a declaration. Delete the shadow, it comes back. Change the declaration, the shadow changes. Everything you watch Crossplane do next is this one sentence, demonstrated at increasing speed.

[23:00]

One last connection before we play with it: this same anatomy — `forProvider`, `providerConfigRef`, Ready/Synced, spec-down-status-up — is what a `Bucket` looks like in AWS, an `IamRolePolicy`, a Redis replication group. Different kind, different provider, *identical shape*. We're going to prove how well you've internalized it — by putting it under attack.

## Phase 8 — The Drift Fight (23:00 – 27:30)

[23:00]

Now the segment this whole episode exists for. I'm going to do the thing every ops team fears: hand-edit production. Watch.

[23:10 — terminal]

```bash
kubectl -n demo-team-a delete configmap welcome
kubectl -n demo-team-a get configmap welcome   # NotFound
```

Gone. Now — in Terraform-world, this is the part where nothing happens until the next pipeline run. In Crossplane-world, the provider is watching that managed resource, and it polls and watches actual state. "What exists is not what was asked for." A level-triggered controller doesn't care *how* it diverged. Console click, defiant colleague, cosmic ray — same answer: fix it.

[23:50 — poll loop]

```bash
while ! kubectl -n demo-team-a get configmap welcome &>/dev/null; do
  echo healing...; sleep 5
done
```

[24:30 — healed]

And it's back. Usually under a minute. I fought the control plane, and the control plane won.

[24:45]

Deletion was attack one. Attack two — someone doesn't delete, they *edit*:

```bash
kubectl -n demo-team-a patch configmap welcome \
  -p '{"data":{"message":"edited by a human, defiantly"}}'
```

Sneakier — the object exists, `kubectl get` looks fine, but the data is wrong. Drift that pipelines are *specifically* blind to, because the object still exists. Give it a reconcile cycle... and the message is back to what the managed resource says. The provider overwrote the edit.

[25:40]

Attack three — flip it around. What happens if I delete the *managed resource*, not the object?

```bash
kubectl delete object demo-team-a-welcome
kubectl -n demo-team-a get configmap welcome   # NotFound!
```

Cascade delete. The MR owned that ConfigMap, so when I remove the MR, the provider removes the thing. `terraform destroy` — but per-resource, instantly, no plan review screen.

[26:20]

Recap the three attacks and the three correct responses: delete → recreate; edit → revert; delete-the-MR → cascade. That's a control loop doing level-triggered reconciliation. And here's the kicker for the Terraform comparison: Terraform's response to all three is the same — "run plan and find out."

[27:00]

Hold on though — "Crossplane deletes my infrastructure when I delete a YAML object" is also how you *lose* infrastructure by accident. Crossplane thought about that: `removalPolicy`. Default is Delete — what you just saw. But I can set `Orphan`: delete the managed resource, and the real object stays behind, unmanaged. That's how you *adopt* existing infrastructure — you manage it, learn from it, and if you ever want to stop managing it, you walk away without destroying anything. We'll flip that flag live in a second. First — let's build the API.

---

## Phase 9 — XRDs: Publish Your Own Kind (27:30 – 30:30)

[27:30]

Everything so far: Crossplane managing things, one object at a time. It's neat, but honestly Terraform does that too. *This* is the segment Terraform cannot follow.

[27:45]

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

[28:20]

Read what this is: I am defining an API group — `demo.crossplane.io`, my group, next to `apps` and `batch` — with a kind called WebApp, namespaced so teams can own and RBAC-scope them, with a schema: required `slug`, optional `replicas` defaulting to 2, optional `image`. Plain OpenAPI, exactly like any CRD you've written.

[28:50 — terminal]

```bash
kubectl apply -f episodes/01-getting-started/manifests/02-xrd.yaml
kubectl get crd webapps.demo.crossplane.io
kubectl explain webapp
```

Kubernetes just learned a new word. `kubectl explain` teaches it back to me. If I create a WebApp right now, it gets stored... and then sits there forever, because nothing *handles* it yet. There's no controller for "webapp". Interesting state, isn't it? The API exists; the meaning doesn't. Let's give it meaning.

[29:50]

Meaning in Crossplane comes from a Composition. And the reason I slowed down on the XRD is this contrast: with Terraform, if I wrap complexity in a module — the consumer still reads and writes Terraform. Here, the consumer *only ever sees the API*. `kind: WebApp`, three fields, full stop. The complexity lives behind it, in the composition — and that's what a platform *is*. An API with opinions behind it.

---

## Phase 10 — Compositions and Functions (30:30 – 35:00)

[30:30]

The composition is the recipe: when someone creates a WebApp, here's everything they get and how it's built. Ours composes four resources: a namespace, a deployment, a service, and a configmap — a tiny compliant environment for a team's web app.

[30:50]

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

[31:30]

And here's the mental model everyone misses, so let me be really precise. Functions do not create anything. When a WebApp appears, the composition controller starts a **render**: it takes the WebApp — what the user asked for — and passes it into function one. Function one is `patch-and-transform`, a container that takes templates plus patches and returns a list of *desired* resources: "here's the namespace, named from spec.slug; here's the deployment, replicas from spec.replicas, image from spec.image or the default; here's the service; here's the configmap." It returns *paperwork*. Then function two, `auto-ready`, looks at the rendered resources and decides when the WebApp can be called Ready. Then — and only then — the composition controller actually creates and updates those resources and streams their status back into the WebApp. Functions render. Controllers create.

[32:40]

Why is this good? Because the pipeline is pluggable. Don't like patch-and-transform's YAML? Swap in `function-go-templating` and write Helm-style templates. Or KCL. Or write your own function in Python or Go — it's just a container. That's a whole season of this series, and it starts from this exact lab.

[33:10 — terminal]

```bash
kubectl apply -f lab/providers/40-functions.yaml
kubectl get functions -w      # INSTALLED/HEALTHY — same package flow as the provider
kubectl apply -f episodes/01-getting-started/manifests/03-composition.yaml
```

Same install story — functions are packages too, pulled as OCI images, installed by the same package manager. Consistency is a feature.

[33:50 — the killer feature]

Now let me show you something Terraform genuinely cannot do. I can render this composition *completely offline*:

```bash
crossplane beta render manifests/04-webapp.yaml manifests/03-composition.yaml
```

All four resources, printed, exactly as they'd be created — and no cluster was involved. Functions are containers; the render runs them locally. This is `terraform plan` — pure, offline, no state file — and you can run it in CI on every PR to your platform definition. You can *unit-test your platform*.

[34:50]

XRD defines the API. Composition gives it meaning. Now let's use it.

---

## Phase 11 — The Payoff: A WebApp (35:00 – 40:00)

[35:00 — the whole file on screen; let it breathe]

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

[35:40 — terminal]

```bash
kubectl apply -f episodes/01-getting-started/manifests/04-webapp.yaml
kubectl get webapp payments -w
```

Watch the status go Ready — that's auto-ready doing its job, checking all four composed resources. And:

[36:10]

```bash
kubectl -n payments-team get all,cm
```

There it is. The namespace, the deployment — podinfo, running, two replicas — the service, the configmap. One resource in, an environment out. And the status flowed back the other way: the WebApp's conditions summarize everything composed beneath it. You can build dashboards off *that*.

[36:50 — the tree]

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

[37:30 — updates: the chain of loops]

Now updates — this is where it gets philosophically beautiful. Watch what happens when I change the spec:

```bash
kubectl patch webapp payments --type merge -p '{"spec":{"replicas":4}}'
watch kubectl -n payments-team get deployment webapp
```

Four replicas. But think about the chain that just fired: I patched the WebApp — the composition controller re-renders — patch-and-transform copies spec.replicas into the deployment template — the controller updates the composed Deployment — and the *plain Kubernetes* Deployment controller does the rolling update. A chain of control loops, each doing one job, composing into platform behavior. Nobody restarted anything. No pipeline ran. `kubectl patch` to scale an environment.

[38:50 — prove it works]

And it's real infrastructure, so let's use it:

```bash
kubectl -n payments-team port-forward service/webapp 98103:3898 &
curl localhost:9898/
```

[39:20 — delete]

And the final power move — cleanup:

```bash
kubectl delete webapp payments
kubectl get ns payments-team      # NotFound
```

Delete the claim on the API, the platform deletes everything it composed. Nine lines in, one line out, environment completely cleaned. Imagine `kind: Database` behind this pattern. That's a platform.

---

## Phase 12 — The Honest Verdict: Crossplane vs Terraform (40:00 – 44:00)

[40:00 — table on screen]

Time to pay off the promise from the intro. The full, honest comparison.

**Model.** Terraform is a pipeline — plan, apply, exit. Crossplane is a control plane — controllers that reconcile forever. This difference drives *everything* downstream.

**State.** Terraform has a state file: lock it, store it, back it up, never commit it. Crossplane has no state file — the API server is the state, and etcd already solved that problem years ago.

**Drift.** Terraform detects drift when a human or CI runs plan — bolt on a cron. Crossplane *corrects* drift continuously. You watched it. That was the cold open.

**Abstraction.** Terraform modules: consumers still write HCL, still hold credentials, still wait on pipelines. Crossplane XRDs: consumers write nine lines of `kind: WebApp`. Modules are files you call; XRDs are APIs you publish.

**Updates and day-2.** Re-run the pipeline, versus... patch the resource. And GitOps fits for free: Argo CD syncing Crossplane resources is just Argo CD doing what it already does.

[41:40 — and now the case FOR Terraform]

But this table has two columns, and I promised honesty. Terraform is fifteen years old, with providers for nearly everything on Earth. Crossplane's provider ecosystem is younger, and cloud coverage is real but patchier. If your infra is a one-shot, brownfield, or your org already breathes HCL — Terraform is the *correct* answer, and v2 churn means old Crossplane tutorials will actively mislead you today. It's a younger technology and you should price that in.

[42:30 — the litmus test]

So here's the litmus test I use. Ask: *"Who notices when someone changes infrastructure by hand at 2am?"* If the answer is "the next time a human runs a pipeline" — you have a pipeline, and you should know that's what you have. If the answer is "a controller, within a minute" — you have a control plane.

- One-shot builds, brownfield, HCL-fluent org → **Terraform**.
- Infra as a product for many teams, kubectl-and-GitOps as the interface, drift matters → **Crossplane**.
- And in practice: both. Terraform builds the cluster. Crossplane runs inside it. This lab? Terraform built these very VMs, and Crossplane just ran on top of them. No irony wasted.

[43:40 — wrap]

Everything you saw today is in the repo: the install, the provider, the XRD, the composition, every command from this episode in a runnable lab guide — go break it, that's what it's for. Next episode: compositions in depth — real functions, dependencies between resources, versioning your platform API like a product. Subscribe, and I'll see you in the control plane.
