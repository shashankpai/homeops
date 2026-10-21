# Episode 03: Demo Flow Mapping
## Narration Phase → Lab-Guide Section Mapping

| Narration Phase | Time | Lab-Guide Section | Demo Script Step | Key Artifacts |
|---|---|---|---|---|
| 1 — Hook: The 5-Minute Version | 0:00–1:00 | §1 Episode Overview | — (framing) | Standup clock overlay |
| 2 — Triage: The 30-Second Fork | 1:00–3:00 | §6 Triage | STEP 2 | Quoted custom-columns one-liner, staged victims |
| 3 — The False Leads | 3:00–4:30 | §7 The False Leads | STEP 3 | `logs --previous` on both pods (empty vs telling) |
| 4 — Layer 1: The API | 4:30–7:00 | §8 Layer 1 (describe + exit-code decode) | STEP 4 | `describe` block, 137 = 128+9 diagram |
| 5 — Layer 2: Metrics (fix decider) | 7:00–9:30 | §9 Metrics (Panels 1–5) | STEP 5 | `ep03-diag` dashboard, deriv panel full-screen |
| 6 — Layer 3: The Node | 9:30–11:30 | §10 Layer 3 (cgroup build + memory.events) | STEP 6 | POD_UID path build, `oom_kill` confession |
| 7 — Layer 4 + Stop Rule | 11:30–13:00 | §11 Layer 4 (dmesg + stop rule) | STEP 7 | `dmesg` kill record, stop-rule ladder |
| 8 — The Evidence Matrix | 13:00–14:30 | §12 The Evidence Matrix | STEP 8 | Full table (matches `runbook.md` rows) |
| 9 — Outro: The Next Question | 14:30–16:00 | §13 Cleanup / Reset | `make cleanup-ep03` | Episode 4 prevention tease |

## Key Demo Sections

### The staged crime scene (before STEP 2 — lab-guide §5)
demo.sh preflight does all staging:
- ensures payment-service is running (deploys from Episode 1 if missing)
- deploys `crashy` (CrashLoop contrast pod) and waits ~90s for backoff
- triggers a FRESH OOMKill (lab-guide §5 "Trigger the fresh kill") so the
  diagnosis is live, not historical — start it ~4 min before filming

### The triage fork (Phase 2 → STEP 2 — lab-guide §6)
- The single-quoted custom-columns one-liner (zsh-safe — see §6 note and
  Troubleshooting)
- Freeze frame + red circles: `RESTARTS + OOMKilled` vs `CrashLoopBackOff`
- Both victims visible in one output — that's the fork, on real corpses

### The metrics phase (Phase 5 → STEP 5 — lab-guide §9)
- Record with the Episode 3 dashboard open (`oom-diagnosis.json`, uid `ep03-diag`)
- The deriv panel (Panel 5) is the episode's core visual — show it
  full-screen; three shapes, three fixes
- Screen-record the fresh kill's full history (climb + cliff) during
  Section 5 staging for the autopsy replay

### The node phases (Phases 6–7 → STEPS 6–7 — lab-guide §10–11)
- demo.sh builds the cgroup path from the POD UID and runs the ssh
  commands itself (falls back to printed manual commands if ssh fails) —
  keep the fallback output in the edit; it teaches the manual path too
- In this lab node names are IPs (Episode 2 lesson) — demo.sh still
  resolves InternalIP for the general case

## Notes for Video Production

- Kill payment-service ~4 min before filming Phases 4–5 so `--previous`
  logs and the metrics cliff are fresh
- Let crashy accumulate restarts during the whole episode — its backoff
  staircase in the restarts panel is free B-roll
- The evidence-matrix graphic must match `runbook.md` rows exactly —
  same rows, same wording (viewers will print that file)
- If filming across sessions: re-run `make demo-ep03` (it re-stages
  everything, including a fresh kill)
- End-of-episode cleanup shot: `make cleanup-ep03` + the note that
  payment-service's restart counter keeps the kills as evidence

## Quick Reference: Where Each Artifact Is Used

| Artifact | Used In |
|---|---|
| `manifests/crashloop.yaml` | Preflight (contrast victim) — lab-guide §5 |
| `scripts/demo.sh` | The runnable backbone (STEPS 1–8) |
| `scripts/cleanup.sh` | Phase 9 (episode end) |
| `lab-guide.md` | The manual, phase-by-phase path (recording) |
| `runbook.md` | Phase 8 — the printable (referenced as "the screenshot") |
| `promql/queries.md` | Phase 5 (fix decider) — lab-guide §9 |
| `dashboards/oom-diagnosis.json` | Phases 2, 5 — lab-guide §9 panels |
| Episode 1's `payment-service.yaml` | Preflight (deployed if missing) — lab-guide §5 |
