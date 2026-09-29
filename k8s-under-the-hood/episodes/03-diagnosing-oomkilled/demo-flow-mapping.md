# Episode 03: Demo Flow Mapping
## Narration Phase → Lab-Guide / Runbook Section Mapping

| Narration Phase | Time | Demo Script Step | Key Artifacts |
|---|---|---|---|
| 1 Hook | 0:00–1:00 | — (framing) | Standup clock overlay |
| 2 Triage fork | 1:00–3:00 | STEP 2 | custom-columns one-liner, staged victims |
| 3 False leads | 3:00–4:30 | STEP 3 | `logs --previous` on both pods |
| 4 Layer 1 API | 4:30–7:00 | STEP 4 | `describe` block, exit-code decode |
| 5 Layer 2 Metrics | 7:00–9:30 | STEP 5 | 3 queries, Episode 3 dashboard, deriv panel |
| 6 Layer 3 Node | 9:30–11:30 | STEP 6 | cgroup path build, `memory.events` |
| 7 Layer 4 + stop rule | 11:30–13:00 | STEP 7 | `dmesg`, stop-rule ladder |
| 8 Evidence matrix | 13:00–14:30 | STEP 8 | Full table (matches `runbook.md`) |
| 9 Outro | 14:30–16:00 | — | Episode 4 tease |

## Key Demo Sections

### The staged crime scene (before STEP 2)
demo.sh preflight does all staging:
- ensures payment-service is running (deploys from Episode 1 if missing)
- deploys `crashy` (CrashLoop contrast pod) and waits ~90s for backoff
- triggers a FRESH OOMKill so the diagnosis is live, not historical

### The metrics phase (STEP 5 — the fix decider)
- Record with the Episode 3 dashboard open (`oom-diagnosis.json`)
- The deriv panel is the episode's core visual — show it full-screen
- Screen-record ~10 min of history (climb + cliff) for replay

### The node phases (STEPS 6-7)
- demo.sh runs the ssh commands itself (falls back to printed manual
  commands if ssh fails) — keep the fallback output in the edit; it
  teaches the manual path too

## Notes for Video Production

- Kill payment-service ~4 min before filming Phase 4-5 so `--previous`
  logs and the metrics cliff are fresh
- Let crashy accumulate restarts during the whole episode — its backoff
  staircase in the restarts panel is free B-roll
- The evidence-matrix graphic must match `runbook.md` rows exactly
- If filming across sessions: re-run `make demo-ep03` (it re-stages
  everything, including a fresh kill)

## Quick Reference: Where Each Artifact Is Used

| Artifact | Used In |
|---|---|
| `manifests/crashloop.yaml` | Preflight (contrast victim) |
| `scripts/demo.sh` | The runnable backbone (STEPS 1-8) |
| `scripts/cleanup.sh` | Episode end (delete crashloop-demo ns) |
| `runbook.md` | The printable — referenced at Phase 8 as "the screenshot" |
| `promql/queries.md` | Phase 5 (fix decider) |
| `dashboards/oom-diagnosis.json` | Phases 2, 5 (triage + autopsy + deriv panels) |
| Episode 1's `payment-service.yaml` | Preflight (deployed if missing) |
