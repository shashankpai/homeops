# Episode 02: Demo Flow Mapping
## Narration Phase → Lab-Guide Section Mapping

| Narration Phase | Time | Lab-Guide Section | Demo Script Step | Key Artifacts |
|---|---|---|---|---|
| 1 — Intro / Hook | 0:00–1:00 | §1 Episode Overview (table) | — (uses existing/prior state) | `kubectl get pods` two corpses |
| 2 — Theory: The Two Actors | 1:00–3:30 | §2 Learning Objectives, §1 comparison table | — | Eviction signals diagram |
| 3 — Setup: Deploy the Victims | 3:30–5:00 | §4 Prerequisites, §5 Eviction Threshold, §6 Deploy Hogs | demo.sh STEP 1–2 | `manifests/memory-hog.yaml`, `/etc/rancher/k3s/config.yaml` |
| 4 — Baseline | 5:00–6:00 | §7 Baseline | demo.sh STEP 3 | `kubectl describe node` conditions |
| 5 — Trigger: Fill the Node | 6:00–8:00 | §8 Trigger | demo.sh STEP 4 | `/allocate` ramp, Grafana Panel 1 |
| 6 — The Eviction | 8:00–10:00 | §9 The Eviction | demo.sh STEP 5 | `-w` output, eviction event |
| 7 — Metrics Replay | 10:00–12:30 | §12 Metrics | (recorded during STEP 4) | Dashboard panels 1–4, `promql/queries.md` |
| 8 — The Ranking | 12:30–15:00 | §10 Investigation (QoS post-mortem) | demo.sh STEP 6 | Ranking diagram, QoS custom-columns |
| 9 — On the Node | 15:00–17:00 | §11 On the Node | (manual ssh segment) | `journalctl`, config.yaml, dmesg contrast |
| 10 — Comparison Table | 17:00–18:30 | §13 The Comparison Table | demo.sh STEP 7 | Fresh OOMKill re-trigger + both corpses |
| 11 — Prevention + Outro | 18:30–20:00 | §14 Cleanup / Reset | `make cleanup-ep02` | MemoryPressure clearing in metrics |

## Key Demo Sections

### The trigger (Phase 5 → STEP 4)
The heart of the episode. Requirements while recording:
- Grafana dashboard open (Episode 2 — Eviction Investigation), 5s refresh
- Screen-record the FULL drain (~15–20 min wall time) for the Phase 7 replay
- `kubectl get pods -n eviction-demo -w` visible in a second terminal

### The eviction (Phase 6 → STEP 5)
- Freeze on the first `Evicted` status
- The event line ("node was low on resource") is the evidence peak —
  read it aloud, highlight phrase by phrase

### The side-by-side (Phase 10 → STEP 7)
- demo.sh re-triggers payment-service's OOMKill (~3–4 min ramp)
- Record both `kubectl get pods` outputs back to back while the
  narration builds the comparison table

## Notes for Video Production

- Eviction timing is kubelet-paced (housekeeping interval, ~10s after
  threshold crossing) — the script polls; edit out the waits
- The ramp is deliberately slow (2MB/2s per hog) for metrics visibility —
  time-lapse to ~20 s in the edit, keep the threshold crossing real-time
- The node takes a few minutes to clear MemoryPressure after cleanup —
  show the condition flip in Grafana as the closing full-circle shot
- If the demo needs a second take, run `make cleanup-ep02` first and wait
  for MemoryPressure to clear before re-pinning hogs to the same node

## Quick Reference: Where Each Artifact Is Used

| Artifact | Used In |
|---|---|
| `manifests/memory-hog.yaml` | Phase 3 (setup), lab-guide §6 |
| `scripts/demo.sh` | Phases 3–6, 8, 10 (the runnable backbone) |
| `scripts/cleanup.sh` | Phase 11 (full-circle recovery shot) |
| `promql/queries.md` | Phase 7 (metrics replay), lab-guide §12 |
| `dashboards/eviction-investigation.json` | Phases 4, 5, 7 — imported before recording |
| Episode 1's `payment-service.yaml` | Phase 3 (contrast victim, auto-deployed by demo.sh) |
