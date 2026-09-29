# Episode 04: Demo Flow Mapping
## Narration Phase → Demo Script Step Mapping

| Narration Phase | Time | Demo Script Step | Key Artifacts |
|---|---|---|---|
| 1 Hook | 0:00–1:00 | — | YAML diff graphic |
| 2 The fork | 1:00–2:30 | STEP 3 | deriv query + Leak Signature panel |
| 3 Anti-pattern | 2:30–4:30 | STEP 4 | Time-to-Limit panel |
| 4 Fix A (app) | 4:30–6:30 | STEP 5 | `/allocate?mb=80` then `/release` — WS falls |
| 5 Fix B (size) | 6:30–9:30 | STEP 6 (setup) | quantile queries, sized YAML deploy |
| 6 Money shot | 9:30–11:30 | STEP 6 | same `mb=200` → survives; restarts 4 vs 0 |
| 7 Safety net | 11:30–14:00 | STEP 7 | `mb=450` → MemoryNearLimit FIRING, pod alive |
| 8 QoS recap | 14:00–15:00 | — | diagram |
| 9 Checklist | 15:00–16:30 | STEP 8 | 7-line checklist (matches printable) |
| 10 Season wrap | 16:30–17:45 | — | 4-episode system diagram |
| 11 Outro | 17:45–18:30 | — | Season 2 networking tease |

## Key Demo Sections

### The kill restage (STEP 2 — before Phase 2 references it)
demo.sh preflight ensures the bad pod + alert rules; STEP 2 triggers the
Episode 1 kill one final time — record it so the season "bookend" death
is on camera.

### The release (STEP 5 — Phase 4)
`mb=80` then `/release` — the working set FALLING in Grafana is the only
shot in the season where memory goes DOWN. Don't miss capturing it.

### The money shot (STEP 6 — Phase 6)
- `mb=200` on the sized pod — the exact command from Episode 1
- Have the two-pod panel (bad history vs sized live) framed BEFORE firing
- Restart counters panel visible for the `4 vs 0` capture

### The alert firing (STEP 7 — Phase 7)
- Prometheus UI at `/alerts`, 5s refresh
- demo.sh polls the API for `firing` — rehearse once; `for: 1m` means the
  sequence takes ~90s wall time (edit can compress)

## Notes for Video Production

- Phases 4–7 should be one continuous Grafana recording session
- Begin recording before the STEP 2 kill so the bad pod's cliff is in-window
- If re-shooting only the alert section: sized pod must be re-deployed and
  re-ramped (demo.sh STEP 6 then STEP 7 can be re-run)
- The Season 2 tease ("no process listens on a ClusterIP — go check")
  doubles as a standalone short

## Quick Reference: Where Each Artifact Is Used

| Artifact | Used In |
|---|---|
| `manifests/payment-service-sized.yaml` | STEP 6 (the fix) |
| `scripts/demo.sh` | The runnable backbone (STEPS 1–8) |
| `scripts/cleanup.sh` | Episode end (delete sized deployment) |
| `prevention-checklist.md` | Phase 9 — the printable |
| `promql/queries.md` | Phases 2, 5, 7 (fork, sizing, alert) |
| `dashboards/oom-prevention.json` | Phases 2–7 visual backbone |
| `lab/observability/prometheus.yaml` | STEP 1 (alert rules — lab infra) |
| Episode 1's `payment-service.yaml` | Preflight (the victim) |
