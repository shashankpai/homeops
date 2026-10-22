# Episode 1 — Storyboard: Crossplane Getting Started

**Target length:** 22–28 min. **Hook style:** problem-first, like under-the-hood Ep 1.

## Segment map

| # | Segment | Time | Visuals | Beat |
|---|---------|------|---------|------|
| 1 | Cold open | 0:00–1:00 | Screen: two terminals — `terraform apply` vs `kubectl apply` | "What if your infrastructure was just... Kubernetes? No CLI, no state file, no plan. Here's Crossplane doing exactly that, live." Show drift-heal result clip as the promise. |
| 2 | What is Crossplane + Terraform comparison | 1:00–7:00 | Diagram: Terraform (CLI → state → API) vs Crossplane (controller loop → API) | Core teaching act. Comparison table below. Land on: "Terraform automates the *creation*; Crossplane *runs* the thing." |
| 3 | What's installed | 7:00–9:00 | Terminal: pods, CRDs, providers, functions | "The core is 150MB and a controller. Providers are packages." |
| 4 | First managed resource | 9:00–13:00 | `kubectl apply` of Object manifests; READY/SYNCED | "This is a namespace defined as a managed resource. It's Terraform without Terraform." |
| 5 | Drift fight | 13:00–17:00 | Delete the ConfigMap; heal loop timer on screen | The "wow" moment #1. "I just fought the control plane. The control plane won." |
| 6 | Platform API (XRD + Composition) | 17:00–22:00 | XRD → new kind; Composition pipeline; WebApp YAML | The "wow" moment #2: 9-line YAML → namespace + deployment + service + configmap. `crossplane beta trace`. |
| 7 | Cleanup power + recap | 22:00–25:00 | `kubectl delete webapp` → everything gone | "Delete the claim on the API, the platform cleans up." Recap 3 ideas. Tease Ep 2. |

## Segment 2 — on-screen comparison table (the teaching core)

| | Terraform | Crossplane |
|---|---|---|
| Model | CLI run: plan → apply → done | Control plane: controllers reconcile forever |
| State | State file (lock, drift, storage) | Live cluster state (`kubectl` is your view) |
| Drift detection | Next `plan` (or cron) | Continuous (seconds to ~1 min) |
| API | HCL, files, providers as code | Kubernetes CRDs, native `kubectl`/GitOps |
| Who triggers changes | Human/CI runs CLI | Apply to API, controllers act |
| Abstraction | Modules (files you call) | XRD + Composition (APIs you *publish*) |
| Ecosystem | 15+ years, huge registry | Younger; cloud + Kubernetes + functions |
| Great at | Big one-time builds, existing orgs | Ongoing ops, platform teams, self-service infra |

**When to use which (say this verbatim-ish):**
- Use **Terraform** for one-shot provisioning, brownfield, teams already fluent in HCL.
- Use **Crossplane** when infra is a *product* consumed by many teams, when you want GitOps/`kubectl` as the only interface, and when continuous reconciliation matters.
- They coexist fine: Terraform builds the cluster, Crossplane runs on it. (Our lab: Terraform built these VMs — nice callback to under-the-hood.)

## B-roll / assets to prepare

- Terraform-vs-Crossplane loop diagram (segment 2)
- Composition pipeline diagram (segment 6)
- Timer overlay for the drift-heal wait (segment 5)
- End card: series roadmap (ROADMAP.md)

## Retakes

- Segment 5 is timing-sensitive: rehearse the heal wait once before recording; if >45s, cut to time-lapse.
- Segment 6 XRD must be fresh — record before any other take created a WebApp.
