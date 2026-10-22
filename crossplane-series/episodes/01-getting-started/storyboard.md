# Episode 1 — Storyboard: Crossplane Getting Started

**Target length:** ~40 min (long is fine — this is the reference/getting-started episode). **Hook style:** show-the-miracle-first, then build the understanding, like under-the-hood Ep 1.

> Narration is verbatim in `narration.md` (12 phases, timestamped). This file is the production map.

## Segment map

| Phase (narration.md) | Segment | Time | Visuals | Beat |
|---|---------|------|---------|------|
| 1 | Cold open | 0:00–1:30 | Split terminals: hand-delete ConfigMap vs ...it heals | The promise. "Nobody ran anything." |
| 2 | The problem | 1:30–4:00 | Pipeline diagram; state file liabilities | Pipeline model's three structural flaws; consumers read HCL |
| 3 | Control plane model | 4:00–7:00 | Deployment loop reused for infra; side-by-side diagram | The one-sentence thesis. Honesty beat: "it's operators." |
| 4 | Install | 7:00–9:00 | helm upgrade --install; CRD count | "One release. Everything else arrives as packages." v2 version note |
| 5 | Providers | 9:00–13:00 | Provider apply; watch INSTALLED/HEALTHY; new CRD + Deployment appear | Package manager working live: image → CRDs + controllers + SA |
| 6 | ProviderConfig | 13:00–15:00 | The 5-line InjectedIdentity file | Credentials as API resources; vs creds-on-laptop |
| 7 | First managed resources | 15:00–19:00 | Object YAML anatomy; READY/SYNCED; annotations | Spec down, status up. "kubectl get IS terraform state list" |
| 8 | Drift fight | 19:00–23:30 | 3 attacks: delete → heal; edit → revert; delete MR → cascade | The centerpiece. Timer overlay. removalPolicy teaser |
| 9 | XRD | 23:30–26:30 | XRD YAML; kubectl explain | "Kubernetes learned a new word." API vs modules |
| 10 | Composition + functions | 26:30–31:00 | Pipeline YAML; offline `crossplane beta render` | Functions render, controllers create. Offline render = unit-testing the platform |
| 11 | WebApp payoff | 31:00–36:00 | 9-line YAML → environment; trace tree; patch replicas 2→4; curl; delete → clean | Update = chain of control loops. Trace = incident response |
| 12 | Verdict: vs Terraform | 36:00–40:00 | Comparison table; litmus test | Both columns honestly; "who notices a 2am change?"; Terraform built this lab |

## Assets to prepare

- Pipeline-vs-control-plane loop diagram (Phase 2–3)
- Provider package anatomy: image → [CRDs, controllers, SA] (Phase 5)
- Composition render flow: XR → function(s) → rendered resources → controller creates (Phase 10)
- Timer overlay for the drift heal (Phase 8)
- Comparison table graphic (Phase 12) — also the standalone Short
- End card: series roadmap (ROADMAP.md) + repo link

## Cut-downs / derivatives

- Short: "Crossplane vs Terraform in 60 seconds" (Phase 12)
- Short: "I deleted it and the cluster healed it" (Phase 8)
- Short: "9 lines of YAML did all this" (Phase 11)

## Retakes & timing notes

- Phase 8 heal can take up to ~60s — rehearse once; if slow, force a provider pod restart off-camera, or cut to time-lapse.
- Phase 5: record the Provider watch from a clean install (uninstall/reinstall) so `INSTALLED/HEALTHY` flips on camera.
- Phase 11: the WebApp must be fresh — `make cleanup-ep01` between takes; the namespace must NOT pre-exist.
- Two-terminal cold open: pre-position both windows; heal clip should be pre-recorded as backup.
