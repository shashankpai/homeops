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
- The product is an API. Your platform team can publish `kind: WebApp`, and a developer gets a whole compliant environment from a handful of lines of YAML. No HCL, no credentials, no pipeline.

[5:40]

One sentence for it: **Terraform automates the *creation* of infrastructure. Crossplane *runs* infrastructure, the way Kubernetes runs pods.**

[5:50 — honesty beat]

Now, is this magic? No. It's operators. You've installed plenty — cert-manager, external-dns. Crossplane is one very large, very well-organized operator framework for *infrastructure*. If you understand deployments, you already understand half of Crossplane.

[6:10]

The other half is vocabulary, and it's small: providers, provider configs, managed resources, XRDs, compositions, functions. We're going to touch every single one in this episode, on a real cluster. By the end, none of those words will be scary.

[6:30]

The lab — you've seen it in the Kubernetes Under the Hood series: three-node K3s on Proxmox. Terraform built these VMs, which I promise becomes funny later. We're just adding one more thing to it.

---

## Phase 4 — Install Crossplane (7:00 – 9:00)

[7:00 — terminal]

Crossplane installs as one Helm release. That's it:

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace --version 2.0.2 --wait
```

[7:40 — while it runs]

What did we just get? Let me spoil it: Crossplane core is a *package manager* plus a bunch of CRDs. The CRDs are the language — Provider, ProviderConfig, XRD, Composition. The core controllers manage those. And that's genuinely all the "Crossplane" there is. Everything cloud-specific — AWS, GCP, Kubernetes itself — arrives later, as packages.

[8:10 — terminal]

```bash
kubectl get pods -n crossplane-system
kubectl get crd | grep -c crossplane
```

One pod — well, two with the RBAC manager. And look at this: about twenty CRDs, from one chart. This is Crossplane's language definition. Every provider and function we install today gets installed *by* this thing — Crossplane bootstraps itself.

[8:45]

Versions note: we're on v2 — I'll flag where v1 differs as we go, because most tutorials out there are v1 and they will lie to you. Claims are gone, composite resources are namespaced, compositions are always pipelines of functions. Cheat sheet is in the repo notes.

---

## Phase 5 — Providers: Teaching the Control Plane a New Language (9:00 – 14:00)

[9:00]

Let's start this section with a question most tutorials skip, and it's the question that makes everything else click: after we installed Crossplane core — that Helm release from a minute ago — what can it actually *do*?

The honest answer is: almost nothing. And I mean that as praise — it's *by design*. Crossplane core has no idea what an S3 bucket is. It has never heard of Route 53. It doesn't even know what a Kubernetes namespace is — and it's *running inside Kubernetes*. The core is deliberately, structurally ignorant of every infrastructure API on Earth. It knows exactly two jobs: how to *install and run packages*, and how to *manage the lifecycle of resources* those packages define. Everything useful arrives later, from outside.

[9:35 — analogy]

The closest thing in your daily life is a phone out of the box. The operating system is Crossplane core: it can install apps, run them, update them, restart them when they crash — and it ships with *zero apps*. Nobody says "my phone can do video calls" — the *app* does video calls, on top of the OS. The app store is the Crossplane package ecosystem. And the apps are called **providers**.

[9:55]

So when you hear someone say "Crossplane manages AWS" — hear the imprecision, because it matters: *Crossplane* can't manage AWS. A **provider package** — provider-aws — installed *into* Crossplane, can. Same for GCP, Azure, SQL, and the one we'll use today: Kubernetes itself. One control plane, any number of languages, installed one package at a time.

[10:15 — the anatomy]

And here is the anatomy. I want this on screen, because every provider you will ever install — today or in five years — is these **three things, shipped inside one OCI image**:

**1. Vocabulary — the CRDs.** New resource *kinds*, with schema, fields, and validation. provider-kubernetes brings one kind: `Object`. provider-aws brings *hundreds*: `Bucket`, `IAMRole`, `VPC`, `ReplicationGroup`. This is the language the control plane learns.

**2. Workers — the controllers.** A CRD with no controller is just a schema nobody reads — you could apply resources and they'd sit there, inert, forever. The controllers are the running code that watches those resources and goes out and does the work. This is where the intelligence lives.

**3. Identity — the runtime.** The pods those workers run in, and the service accounts they run *as*. Because every worker eventually asks "who am I, when I talk to the API I manage?" — and that has to be an answer, not an accident.

Vocabulary. Workers. Identity. One image. Say it with me once, because we're literally going to watch all three materialize in the next three minutes.

[11:15 — the plan]

Today's provider: `provider-kubernetes` — the provider whose "cloud" is this cluster itself. I picked it for episode one for three reasons. *No cloud account* — you can follow along on kind or k3s at home. *No credentials* — nothing to rotate, nothing to blur on screen. And *full visibility* — everything it does, you can inspect with plain kubectl. And the mental model we're building transfers to provider-aws completely unchanged. This is the safest possible place to learn the pattern properly.

[11:40 — terminal; three files on screen]

Three files, and I want you to notice the *order* — it's deliberate:

```bash
kubectl apply -f lab/providers/10-runtime-config.yaml   # identity first: pin the SA name
kubectl apply -f lab/providers/20-rbac.yaml              # identity second: grant its powers
kubectl apply -f lab/providers/00-provider.yaml           # then: the package
```

Files one and two are the *identity* part of our anatomy, applied **before** the provider exists. That's not demo tidiness — that's a production principle: never let a provider's workers boot into more privilege than you planned for them. Identity before code. If you take one security habit from this episode, take this one.

Quickly, what each file does, because we'll lean on this in the next section. The *runtime config* says: "the provider's pods will run as a service account named `provider-kubernetes`" — a fixed, predictable name. The *RBAC* file binds that service account to a role that says what it may do. Today, for teaching, that role is broad — it can manage anything. In production you'd tighten it to exactly the kinds the provider handles: it manages namespaces, it gets namespaces — nothing else. **The provider is exactly as powerful as the role you give it.** That's not a caveat, that's a *feature* — more on that contrast in a second.

[12:45 — watch the install]

Now the package itself. Apply it, and watch the package manager do its work — I never get tired of this part:

```bash
kubectl apply -f lab/providers/00-provider.yaml
kubectl get provider provider-kubernetes -w
```

```
PACKAGE                        INSTALLED   HEALTHY
provider-kubernetes:v1.0.0
provider-kubernetes:v1.0.0     True
provider-kubernetes:v1.0.0     True        True
```

Here's what happened behind those two words, step by step. The `Provider` resource is nothing but a pointer: "install this image". The core controller pulled the OCI image from the package registry, read its manifest, and executed an *installation*:

**Installed: True** means the image was pulled, and everything inside it was extracted and applied — CRDs registered, controllers deployed, runtime created. The app finished installing.

**Healthy: True** means those controllers are *up and serving* — running, connected to the API, ready to reconcile. The app isn't just installed, it's working.

And notice — those two words are a *built-in diagnostic*. If Installed never flips True, your problem is getting the image: registry, network, version tag. If Installed is True but Healthy won't come, your problem is the controllers: crash-looping, or — and hold this thought for the next phase — *identity*. "Which word is stuck" is half of Crossplane debugging, before you've run a single other command.

[13:35 — the vocabulary appears]

Now let's prove the vocabulary arrived. I never wrote any of this:

```bash
kubectl get crd | grep kubernetes.crossplane.io
kubectl explain object
kubectl get deployments -n crossplane-system
```

A brand-new CRD: `kind: Object`. And it's *documented* — `kubectl explain` teaches it back to me, because the schema shipped inside the image. This is the moment I've watched surprise even experienced Kubernetes people — so let it land: **the resource kinds came out of the package.** You didn't write a CRD for "namespaces-as-managed-resources". You didn't download one. You installed a provider, and your cluster's API grew new words, on demand, from an image pull. That is what "provider" *means*: vocabulary plus workers plus identity, arriving as one unit.

And that new Deployment in crossplane-system — those are the workers. Controller pods whose entire purpose in life, from now until we uninstall them, is to watch `Object` resources and make reality match them. They're in there *right now*, watching an empty world, waiting for their first job. Let's give them one more piece before we do — identity.

---

## Phase 6 — ProviderConfig: Identity, All the Way to the Cloud (14:00 – 19:00)

[14:00]

Every API in existence asks the same first question: *who's asking?* You've lived this — every kubectl you've ever run was authenticated and authorized before the cluster lifted a finger. So here's the situation: we now have controller pods in this cluster whose job is to create and manage objects in... this cluster. And when they show up at the API server, the API server is going to card them, exactly like it cards you. **A provider needs an identity to do its job.** The ProviderConfig is where that identity is declared.

[14:30 — how pods authenticate at all]

Let's zoom out for ninety seconds and make sure the mechanics are solid, because everything else today builds on it. How does *any* pod talk to the Kubernetes API?

When you run kubectl, the request carries *your* credentials from your kubeconfig. A pod has no kubeconfig — what it has is a **service account**. Kubernetes automatically projects a token for that service account into every pod, at a well-known path, as a mounted volume. When the provider's controller wants to talk to the API server, it reads that token and presents it — and the API server says: "you are the `provider-kubernetes` service account." Everything the pod can do is then exactly what RBAC says that service account can do. Token in, authority out. That's the whole mechanism — no magic.

Which means when our ProviderConfig says this:

```yaml
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
```

...one word is doing all the work: `InjectedIdentity` means **use the identity the controller already has — its own pod's service account.** The one we named in the runtime config, the one we carefully RBAC-bound *before* the provider existed. That's why those three files in the last phase went in that order. The pieces snap together: name the SA, bind the SA, then tell the provider "you *are* the SA." For managing things in your own cluster, the identity you need already exists — creating a secret to hold it would just be one more thing to leak.

[15:50 — the cloud question]

Now — the question that actually matters for your career, not just this homelab: **what about the cloud?** A service account token is a Kubernetes thing. AWS has never heard of it. When provider-aws creates a bucket, it calls the AWS API, and AWS wants *AWS credentials*. How does the bridge work? There are two patterns, and knowing both — and when to use each — is the difference between a toy platform and a real one.

**Pattern one: static credentials in a Secret.** The classic. You create an IAM user (or role) for Crossplane, generate a key, store it in a Kubernetes Secret, and the ProviderConfig points at it:

```yaml
spec:
  credentials:
    source: Secret
    secretRef:
      name: aws-creds
      key: key
```

The provider reads that Secret at reconcile time and signs its AWS calls. Simple, works everywhere, on any cluster, in any cloud, today. The trade-off: that key is long-lived. It's a copy of power, sitting in a Secret, and it has to be rotated — on a schedule, forever, or it quietly becomes your biggest liability. Kubernetes secrets are only as protected as your cluster's RBAC and etcd encryption.

**Pattern two: Workload Identity — no credentials at all.** The modern answer, and the reason `InjectedIdentity` scales beyond this demo. Here's the trick, and it's genuinely elegant: you register your *cluster itself* with the cloud as an OIDC identity provider. The cloud says: "I will trust tokens signed by this cluster." Then you annotate a service account with the cloud role it should map to. When provider-aws needs to act, its controller presents its service-account token — the same projected token from a minute ago — and the cloud exchanges it, via OIDC federation, for short-lived cloud credentials. Keys are minted on demand, expire in hours, and *nobody ever stores one*. On EKS this is IRSA; on GKE, Workload Identity Federation; on AKS and self-managed clusters, plain OIDC federation — same idea, different names. And here's the kicker: from the ProviderConfig's point of view, it *looks* like InjectedIdentity — "use my own identity" — because the federation does the translation. The pattern you learned in this homelab lab *is* the production pattern.

[17:30 — the indirection, and why it's designed this way]

Step back and look at the architecture, because there's a deliberate layer of indirection here — and the indirection is the value:

```
managed resource  ──providerConfigRef──▶  ProviderConfig  ──▶  the actual identity
     (I want a bucket)                      (how to authenticate)     (SA / Secret / OIDC role)
```

Every managed resource points at a ProviderConfig *by name*. The config is the only thing that knows where the identity lives. And because identity is a *resource in the API* — addressable, swappable, auditable — three things become possible that the "credentials in a pipeline" world can't give you:

**Separation of powers.** The platform team creates the ProviderConfig; they're the only humans who ever touch credentials. App teams create managed resources that *reference* it. They get the power without ever seeing the secret.

**Multiple identities, same cluster.** Two configs — `prod` and `sandbox` — pointing at different cloud accounts. A managed resource's one-line `providerConfigRef` decides which world it lands in. Retarget by editing one field.

**Central rotation.** When the static key expires, you update *one Secret*, and every resource using that config picks up the new credentials on its next reconcile — no pipelines to rerun, no laptops to hunt down.

And one detail worth knowing, because it explains the name: our config is called `default` because when a managed resource *doesn't* name a config, the provider looks for one with exactly that name. "default" is the fallback. In a real platform you might have a dozen configs and never use the default at all — but nothing breaks the day you forget to reference one.

[18:45 — apply it]

```bash
kubectl apply -f lab/providers/30-provider-config.yaml
kubectl get providerconfigs.kubernetes.crossplane.io
```

Installed, identity granted, zero secrets on my screen — the most powerful thing in this episode is the thing I *didn't* have to type. The workers are running, they know who they are. Time to hand them their first job — and study the shape of it carefully, because it's the shape of everything.

## Phase 7 — Managed Resources: The Atom of Crossplane (19:00 – 25:00)

[19:00]

Everything in Crossplane, no matter how sophisticated the abstraction, eventually bottoms out in the thing we're about to create. A **managed resource**. The atom.

Definition, in one sentence: *a managed resource is one piece of real-world infrastructure, expressed as a Kubernetes resource, and kept correct by a provider's controller.* One row in your infrastructure — as a YAML object in etcd.

[19:30 — the manifest, full screen; take your time]

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

[20:00 — field by field]

`kind: Object` — the kind our provider installed in the last phase. provider-kubernetes's entire product line is one generic kind: "any Kubernetes object". Other providers have rich kind libraries — `Bucket`, `Cluster`, `ReplicationGroup`.

`spec.providerConfigRef: name: default` — *who do I act as?* Straight back to the last phase. This is the pointer that connects a piece of infrastructure to its identity — and notice it's a pointer, not the credential itself. Change this one line, and this namespace gets managed under a different identity.

And now the big one: `spec.forProvider`. **Everything I actually want, lives here.** Read what's inside — apiVersion, kind, metadata — that's not "YAML inspired by Kubernetes". That *is* Kubernetes YAML. The entire object I want to exist is embedded, verbatim, under `forProvider.manifest`. Same for a cloud resource: the `forProvider` block of an S3 bucket holds region, versioning, encryption — the API's own fields, namespaced under one wrapper. The wrapper is Crossplane's; the content is the remote API's.

That's a quietly powerful design choice: **you're not learning a new language for each cloud.** The knowledge you already have of each API transfers inside `forProvider`; Crossplane only ever asks you to learn the wrapper. Terraform asks you to learn HCL *and* its resource model *and* the cloud's semantics. Crossplane asks for the semantics only.

[21:40 — apply, watch]

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

[23:10 — spec down, status up]

Now the contract underneath, and it's the oldest one in Kubernetes: **spec goes down, status comes up.** Everything I wrote was `forProvider` — my desire, handed to the API server. And everything the provider learned, it writes back in two other places: `status.atProvider` — what it *observed*, the real object as it actually is, your `terraform show` equivalent — and those two conditions. Desired state, down. Observed state, up. The gap between them is the controller's entire to-do list, every minute of every day.

[23:40 — the real thing]

Proof time:

```bash
kubectl get ns demo-team-a
kubectl -n demo-team-a get configmap welcome -o yaml | grep -A6 metadata
```

There it is — a namespace, created by a controller. And look at the annotations on the managed resource itself: `crossplane.io/external-name`, create-succeeded timestamps. The provider *signed its work*, and the ConfigMap's field manager says `provider-kubernetes/demo-team-a-welcome` — exactly the way a Deployment owner-references its ReplicaSets. Which means there is no state file holding "I created this": the ownership lives in the API, where anything can read it. `kubectl get` — what you just did — *is* `terraform state list`. All of it. Forever.

[24:30 — the flip]

And here's the mental flip that separates people who *get* Crossplane from people who use it. Before today, you probably thought of the real object — the namespace, the database — as the *real* thing, and any record of it as a shadow. Managed resources reverse that: **the managed resource in the API is the source of truth; the real object is the shadow.** The cloud object, the namespace, the ConfigMap — they're just the *current output* of a declaration. Delete the shadow, it comes back. Change the declaration, the shadow changes. Everything you watch Crossplane do next is this one sentence, demonstrated at increasing speed.

[25:00]

One last connection before we play with it: this same anatomy — `forProvider`, `providerConfigRef`, Ready/Synced, spec-down-status-up — is what a `Bucket` looks like in AWS, an `IamRolePolicy`, a Redis replication group. Different kind, different provider, *identical shape*. We're going to prove how well you've internalized it — by putting it under attack.

## Phase 8 — The Drift Fight (25:00 – 29:30)

[25:00]

Now the segment this whole episode exists for. I'm going to do the thing every ops team fears: hand-edit production. Watch.

[25:10 — terminal]

```bash
kubectl -n demo-team-a delete configmap welcome
kubectl -n demo-team-a get configmap welcome   # NotFound
```

Gone. Now — in Terraform-world, this is the part where nothing happens until the next pipeline run. In Crossplane-world, the provider is watching that managed resource, and it polls and watches actual state. "What exists is not what was asked for." A level-triggered controller doesn't care *how* it diverged. Console click, defiant colleague, cosmic ray — same answer: fix it.

[25:50 — poll loop]

```bash
while ! kubectl -n demo-team-a get configmap welcome &>/dev/null; do
  echo healing...; sleep 5
done
```

[26:30 — healed]

And it's back — about ten seconds in this lab. I fought the control plane, and the control plane won.

[26:45]

Deletion was attack one. Attack two — someone doesn't delete, they *edit*:

```bash
kubectl -n demo-team-a patch configmap welcome \
  -p '{"data":{"message":"edited by a human, defiantly"}}'
```

Sneakier — the object exists, `kubectl get` looks fine, but the data is wrong. Drift that pipelines are *specifically* blind to, because the object still exists. Give it a reconcile cycle — we set the provider's poll to thirty seconds — and the message is back to what the managed resource says. The provider overwrote the edit. One footnote worth knowing: that works because we pinned provider-kubernetes v1.2.0, which uses server-side apply. Older versions only compare against an annotation and would *never* notice this edit.

[27:40]

Attack three — flip it around. What happens if I delete the *managed resource*, not the object?

```bash
kubectl delete object demo-team-a-welcome
kubectl -n demo-team-a get configmap welcome   # NotFound!
```

Cascade delete. The MR owned that ConfigMap, so when I remove the MR, the provider removes the thing. `terraform destroy` — but per-resource, instantly, no plan review screen.

[28:20]

Recap the three attacks and the three correct responses: delete → recreate; edit → revert; delete-the-MR → cascade. That's a control loop doing level-triggered reconciliation. And here's the kicker for the Terraform comparison: Terraform's response to all three is the same — "run plan and find out."

[29:00]

Hold on though — "Crossplane deletes my infrastructure when I delete a YAML object" is also how you *lose* infrastructure by accident. Crossplane thought about that: `deletionPolicy`. Default is Delete — what you just saw. But I can set `Orphan`: delete the managed resource, and the real object stays behind, unmanaged. That's how you *adopt* existing infrastructure — you manage it, learn from it, and if you ever want to stop managing it, you walk away without destroying anything. We'll flip that flag live in a second. First — let's build the API.

---

## Phase 9 — XRDs: Publish Your Own Kind (29:30 – 32:30)

[29:30]

Everything so far: Crossplane managing things, one object at a time. It's neat, but honestly Terraform does that too. *This* is the segment Terraform cannot follow.

[29:45]

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

[30:20]

Read what this is: I am defining an API group — `demo.crossplane.io`, my group, next to `apps` and `batch` — with a kind called WebApp, namespaced so teams can own and RBAC-scope them, with a schema: required `slug`, optional `replicas` defaulting to 2, optional `image`. Plain OpenAPI, exactly like any CRD you've written.

[30:50 — terminal]

```bash
kubectl apply -f episodes/01-getting-started/manifests/02-xrd.yaml
kubectl get crd webapps.demo.crossplane.io
kubectl explain webapp
```

Kubernetes just learned a new word. `kubectl explain` teaches it back to me. If I create a WebApp right now, it gets stored... and then sits there forever, because nothing *handles* it yet. There's no controller for "webapp". Interesting state, isn't it? The API exists; the meaning doesn't. Let's give it meaning.

[31:50]

Meaning in Crossplane comes from a Composition. And the reason I slowed down on the XRD is this contrast: with Terraform, if I wrap complexity in a module — the consumer still reads and writes Terraform. Here, the consumer *only ever sees the API*. `kind: WebApp`, three fields, full stop. The complexity lives behind it, in the composition — and that's what a platform *is*. An API with opinions behind it.

---

## Phase 10 — Compositions and Functions (32:30 – 37:00)

[32:30]

The composition is the recipe: when someone creates a WebApp, here's everything they get and how it's built. Ours composes three resources: a deployment, a service, and a configmap — a tiny compliant environment for a team's web app, inside the team's own namespace. Why no Namespace resource? Because a namespaced WebApp can only compose things *in its own namespace*; the namespace is something the platform team creates once per team.

[32:50]

But first — v2 changed how compositions work, and it's a change for the better. In v1, a composition had built-in patching logic and you'd have these enormous YAML files full of patch rules. In v2, a composition is a **pipeline of functions**. Look at the shape:

```yaml
mode: Pipeline
pipeline:
  - step: patch-and-transform
    functionRef: {name: function-patch-and-transform}
    input:
      resources: [deployment, service, configmap...]
  - step: automatically-mark-ready
    functionRef: {name: function-auto-ready}
```

[33:30]

And here's the mental model everyone misses, so let me be really precise. Functions do not create anything. When a WebApp appears, the composition controller starts a **render**: it takes the WebApp — what the user asked for — and passes it into function one. Function one is `patch-and-transform`, a container that takes templates plus patches and returns a list of *desired* resources: "here's the deployment, replicas from spec.replicas, image from spec.image or the default; here's the service; here's the configmap." It returns *paperwork*. It also returns readiness checks — the deployment counts as ready when it's Available; the service and configmap are ready on creation. Then function two, `auto-ready`, looks at the rendered resources and decides when the WebApp can be called Ready. Those readiness checks matter: plain Kubernetes objects don't report a Ready condition, and without them the WebApp would sit at 'unready' forever. Then — and only then — the composition controller actually creates and updates those resources and streams their status back into the WebApp. Functions render. Controllers create.

[34:40]

Why is this good? Because the pipeline is pluggable. Don't like patch-and-transform's YAML? Swap in `function-go-templating` and write Helm-style templates. Or KCL. Or write your own function in Python or Go — it's just a container. That's a whole season of this series, and it starts from this exact lab.

[35:10 — terminal]

```bash
kubectl apply -f lab/providers/40-functions.yaml
kubectl get functions -w      # INSTALLED/HEALTHY — same package flow as the provider
kubectl apply -f episodes/01-getting-started/manifests/03-composition.yaml
```

Same install story — functions are packages too, pulled as OCI images, installed by the same package manager. Consistency is a feature.

[35:50 — the killer feature]

Now let me show you something Terraform genuinely cannot do. I can render this composition *completely offline*:

```bash
crossplane render episodes/01-getting-started/manifests/04-webapp.yaml \
  episodes/01-getting-started/manifests/03-composition.yaml lab/providers/40-functions.yaml
```

All three resources, printed, exactly as they'd be created — and no cluster was involved. Functions are containers; the render runs them locally. This is `terraform plan` — pure, offline, no state file — and you can run it in CI on every PR to your platform definition. You can *unit-test your platform*.

[36:50]

XRD defines the API. Composition gives it meaning. Now let's use it.

---

## Phase 11 — The Payoff: A WebApp (37:00 – 42:00)

[37:00 — the whole file on screen; let it breathe]

This is everything a developer writes — into the team's namespace, which the platform team created once:

```yaml
apiVersion: demo.crossplane.io/v1alpha1
kind: WebApp
metadata: {name: payments, namespace: payments-team}
spec:
  slug: payments
  replicas: 2
```

Seven lines. No deployment YAML, no service YAML, no configmap YAML, no copying the "standard deployment" from the last team's repo. They ask for an app; the platform does the rest.

[37:40 — terminal]

```bash
kubectl apply -f episodes/01-getting-started/manifests/00-team-namespace.yaml
kubectl apply -f episodes/01-getting-started/manifests/04-webapp.yaml
kubectl -n payments-team get webapp payments -w
```

Watch the status go Ready — that's auto-ready doing its job, checking all three composed resources. And:

[38:10]

```bash
kubectl -n payments-team get all,cm
```

There it is. The deployment — podinfo, running, two replicas — the service, the configmap. One resource in, an environment out. And the status flowed back the other way: the WebApp's conditions summarize everything composed beneath it. You can build dashboards off *that*.

[38:50 — the tree]

Now the tool that will follow you around forever:

```bash
crossplane beta trace webapp/payments -n payments-team
```

```
NAME                                         SYNCED   READY   STATUS
WebApp/payments (payments-team)              True     True    Available
├─ Deployment/webapp (payments-team)
├─ ConfigMap/webapp-config (payments-team)
└─ Service/webapp (payments-team)
```

The full dependency tree, live. When something's wrong, you don't guess — you trace, you find which composed resource is unhappy, you look at *its* events. Incident response for infrastructure, the kubectl way.

[39:30 — updates: the chain of loops]

Now updates — this is where it gets philosophically beautiful. Watch what happens when I change the spec:

```bash
kubectl -n payments-team patch webapp payments --type merge -p '{"spec":{"replicas":4}}'
watch kubectl -n payments-team get deployment webapp
```

Four replicas. But think about the chain that just fired: I patched the WebApp — the composition controller re-renders — patch-and-transform copies spec.replicas into the deployment template — the controller updates the composed Deployment — and the *plain Kubernetes* Deployment controller does the rolling update. A chain of control loops, each doing one job, composing into platform behavior. Nobody restarted anything. No pipeline ran. `kubectl patch` to scale an environment.

[40:50 — prove it works]

And it's real infrastructure, so let's use it:

```bash
kubectl -n payments-team port-forward service/webapp 98101:3898 &
curl localhost:9898/
```

[41:20 — delete]

And the final power move — cleanup:

```bash
kubectl -n payments-team delete webapp payments
kubectl -n payments-team get all,cm      # composed resources gone
```

Delete the WebApp on the API, the platform deletes everything it composed. Seven lines in, one line out, environment completely cleaned. Imagine `kind: Database` behind this pattern. That's a platform.

---

## Phase 12 — The Honest Verdict: Crossplane vs Terraform (42:00 – 46:00)

[42:00 — table on screen]

Time to pay off the promise from the intro. The full, honest comparison.

**Model.** Terraform is a pipeline — plan, apply, exit. Crossplane is a control plane — controllers that reconcile forever. This difference drives *everything* downstream.

**State.** Terraform has a state file: lock it, store it, back it up, never commit it. Crossplane has no state file — the API server is the state, and etcd already solved that problem years ago.

**Drift.** Terraform detects drift when a human or CI runs plan — bolt on a cron. Crossplane *corrects* drift continuously. You watched it. That was the cold open.

**Abstraction.** Terraform modules: consumers still write HCL, still hold credentials, still wait on pipelines. Crossplane XRDs: consumers write a handful of lines of `kind: WebApp`. Modules are files you call; XRDs are APIs you publish.

**Updates and day-2.** Re-run the pipeline, versus... patch the resource. And GitOps fits for free: Argo CD syncing Crossplane resources is just Argo CD doing what it already does.

[43:40 — and now the case FOR Terraform]

But this table has two columns, and I promised honesty. Terraform is fifteen years old, with providers for nearly everything on Earth. Crossplane's provider ecosystem is younger, and cloud coverage is real but patchier. If your infra is a one-shot, brownfield, or your org already breathes HCL — Terraform is the *correct* answer, and v2 churn means old Crossplane tutorials will actively mislead you today. It's a younger technology and you should price that in.

[44:30 — the litmus test]

So here's the litmus test I use. Ask: *"Who notices when someone changes infrastructure by hand at 2am?"* If the answer is "the next time a human runs a pipeline" — you have a pipeline, and you should know that's what you have. If the answer is "a controller, within a minute" — you have a control plane.

- One-shot builds, brownfield, HCL-fluent org → **Terraform**.
- Infra as a product for many teams, kubectl-and-GitOps as the interface, drift matters → **Crossplane**.
- And in practice: both. Terraform builds the cluster. Crossplane runs inside it. This lab? Terraform built these very VMs, and Crossplane just ran on top of them. No irony wasted.

[45:40 — wrap]

Everything you saw today is in the repo: the install, the provider, the XRD, the composition, every command from this episode in a runnable lab guide — go break it, that's what it's for. Next episode: compositions in depth — real functions, dependencies between resources, versioning your platform API like a product. Subscribe, and I'll see you in the control plane.
