# Episode 1 — Storyboard: Crossplane Getting Started

**Target length:** ~45 min (long is fine — this is the reference/getting-started episode). **Hook style:** show-the-miracle-first, then build the understanding, like under-the-hood Ep 1.

> Narration is verbatim in `narration.md` (12 phases, timestamped). This file is the production map.
> **Phases 5–7 are the conceptual core** — providers, identity, managed resources — paced slowly on purpose (~14 min combined). Every later episode stands on them; give them the best takes.

## Segment map

| Phase (narration.md) | Segment | Time | Visuals | Beat |
|---|---------|------|---------|------|
| 1 | Cold open | 0:00–1:30 | Split terminals: hand-delete ConfigMap vs ...it heals | The promise. "Nobody ran anything." |
| 2 | The problem | 1:30–4:00 | Pipeline diagram; state file liabilities | Pipeline model's three structural flaws; consumers read HCL |
| 3 | Control plane model | 4:00–7:00 | Deployment loop reused for infra; side-by-side diagram | The one-sentence thesis. Honesty beat: "it's operators." |
| 4 | Install | 7:00–9:00 | helm upgrade --install; CRD count | "One release. Everything else arrives as packages." v2 version note |
| 5 | **Providers — the core, take your time** | 9:00–14:00 | App-store analogy; vocabulary/workers/identity anatomy; Provider -w; new CRD + Deployment appear | "Core can do nothing — by design." Installed vs Healthy = half of debugging. CRDs come *out of the package*. Security: SA+RBAC is real least-privilege work |
| 6 | **ProviderConfig — identity without secrets** | 14:00–17:00 | The 5-line InjectedIdentity file; credential-source table | "Every API cards you." Identity as a resource: separation, swapping, rotation. Why the name is `default` |
| 7 | **Managed resources — the atom** | 17:00–23:00 | Field-by-field YAML walk; READY/SYNCED -w; annotations on the real object | forProvider = remote API's own YAML embedded. "Synced = messenger, Ready = package." Spec down/status up. **The flip: the MR is the truth, the object is the shadow** |
| 8 | Drift fight | 23:00–27:30 | 3 attacks: delete → heal; edit → revert; delete MR → cascade | The centerpiece. Timer overlay. removalPolicy teaser |
| 9 | XRD | 27:30–30:30 | XRD YAML; kubectl explain | "Kubernetes learned a new word." API vs modules |
| 10 | Composition + functions | 30:30–35:00 | Pipeline YAML; offline `crossplane beta render` | Functions render, controllers create. Offline render = unit-testing the platform |
| 11 | WebApp payoff | 35:00–40:00 | 9-line YAML → environment; trace tree; patch replicas 2→4; curl; delete → clean | Update = chain of control loops. Trace = incident response |
| 12 | Verdict: vs Terraform | 40:00–44:00 | Comparison table; litmus test | Both columns honestly; "who notices a 2am change?"; Terraform built this lab |

## Assets to prepare

- Pipeline-vs-control-plane loop diagram (Phase 2–3)
- Provider anatomy: one image → [CRDs, controllers, SA] — leave on screen during Phase 5
- Managed-resource anatomy card: forProvider / providerConfigRef / atProvider / READY+SYNCED — leave on screen during Phase 7
- "Synced = messenger, Ready = package" caption card (Phase 7)
- Composition render flow: XR → function(s) → rendered resources → controller creates (Phase 10)
- Timer overlay for the drift heal (Phase 8)
- Comparison table graphic (Phase 12) — also the standalone Short
- End card: series roadmap (ROADMAP.md) + repo link

## Cut-downs / derivatives

- Short: "Crossplane vs Terraform in 60 seconds" (Phase 12)
- Short: "I deleted it and the cluster healed it" (Phase 8)
- Short: "9 lines of YAML did all this" (Phase 11)
- Short: "What is a Crossplane provider, really?" (Phase 5)

## Retakes & timing notes

- Phases 5–7 deserve the most takes: the Provider `-w` (INSTALLED→Healthy flipping) must be captured from a clean install (uninstall/reinstall first) so the conditions flip live on camera.
- Phase 7: record the READY/SYNCED `-w` fresh too; have the anatomy card ready to cut to while the apply happens.
- Phase 8 heal can take up to ~60s — rehearse once; if slow, force a provider pod restart off-camera, or cut to time-lapse.
- Phase 11: the WebApp must be fresh — `make cleanup-ep01` between takes; the namespace must NOT pre-exist.
- Two-terminal cold open: pre-position both windows; heal clip should be pre-recorded as backup.
