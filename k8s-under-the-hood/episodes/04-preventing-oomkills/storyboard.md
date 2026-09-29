# How do you prevent Kubernetes OOMKills?
## Full Visual Storyboard

> **Duration:** ~18 minutes · **Format:** season finale, full-circle
> **Principle:** every concept ENDS with proof — the same load that killed
> the pod in Episode 1 survives by the closing act.

---

## Visual Style Guide

(Same conventions as Episodes 1-3)

- **The two-pod split** (bad vs sized) recurs in panels, terminals, and YAML —
  always: bad pod LEFT (red-ish), sized pod RIGHT (green-ish)
- **Math moments** (sizing, time-to-limit) render as big-type arithmetic
- **The alert state** (`PENDING → FIRING`) shown full-screen from the
  Prometheus UI
- Grafana Episode 4 dashboard is the episode's visual backbone

---

## Key Visual Sequences

### Sequence A — The Bigger Number (hook, 0:00–1:00)

- Cold open: a YAML diff — `memory: 128Mi → 512Mi` — with a big red ✗
- "Most teams answer prevention with a bigger number."

### Sequence B — The Fork (1:00–2:30)

```
        deriv(working_set)
        linear ↗ forever        plateaus ──┐
             ↓                            ↓
           LEAK                      UNDER-SIZED
      fix the APP                fix the PLATFORM
   (no YAML fixes a leak)        (size from DATA)
```

### Sequence C — The Anti-Pattern Math (2:30–4:30)

```
time-to-limit = (limit − WS) / growth

  128Mi  →  ~2 min runway
  512Mi  →  ~8 min runway
  quadruple the limit, buy 6 minutes
  "you rescheduled the failure to 3am"
```

- Big-type arithmetic; the time-to-limit Grafana panel live beside it

### Sequence D — The Release (Fix A, 4:30–6:30)

- Grafana: working set climbing... `/release` fired... **falling**
- The only fix that reverses a leak — emphasize with a slow zoom on
  the falling line

### Sequence E — The Sizing Math (6:30–9:30)

```
p95 measured:    ~225Mi
× 2 headroom:     ~450Mi
round:            512Mi
requests == limits → Guaranteed (payment path gets the armor)
```

- Then the YAML reveal of `payment-service-sized.yaml`

### Sequence F — THE MONEY SHOT (9:30–11:30)

- Split Grafana: bad pod's history (climb-ceiling-cliff) beside the sized
  pod's live climb — which flattens at 44% and STAYS
- Then `kubectl get pods`: `RESTARTS 4` vs `RESTARTS 0`
- Full-frame text: **SAME LOAD. ZERO RESTARTS.**
- Hold 3 seconds. This is the thumbnail candidate too.

### Sequence G — The Alert Firing (11:30–14:00)

- Push sized pod past 90% (`mb=450`)
- Prometheus UI full-screen: `MemoryNearLimit` → `PENDING` → `FIRING`
- Side by side: the alert FIRING while the pod is STILL RUNNING
- "A human with 20 minutes beats a kernel with a SIGKILL."

### Sequence H — The QoS Asymmetry Recap (14:00–15:00)

```
eviction (kubelet):          OOMKill (kernel):
  BestEffort   first           QoS means NOTHING
  Burstable    middle          a limit is a limit
  Guaranteed   last
```

### Sequence I — The Checklist (15:00–16:30)

- Full-frame 7-line checklist, lines appearing as narrated
- Matches `prevention-checklist.md` exactly (the printable)

### Sequence J — Season System Diagram (16:30–17:45)

```
Ep 1: the kill         WHO (kernel)
Ep 2: the other killer WHO ELSE (kubelet)
Ep 3: the runbook     HOW to find out
Ep 4: the fix         HOW to prevent
```

---

## Section-by-Section Storyboard

| Phase | Time | Visuals | Action |
|---|---|---|---|
| 1 Hook | 0:00–1:00 | Seq A | YAML diff, bigger-number anti-hook |
| 2 The fork | 1:00–2:30 | Seq B | deriv shapes, two fix paths |
| 3 Anti-pattern | 2:30–4:30 | Seq C | time-to-limit math, live panel |
| 4 Fix A (app) | 4:30–6:30 | Seq D | /release, working set falls |
| 5 Fix B (size) | 6:30–9:30 | Seq E | p95 → headroom → YAML |
| 6 Money shot | 9:30–11:30 | Seq F | same load survived, restarts 4 vs 0 |
| 7 Safety net | 11:30–14:00 | Seq G | alert PENDING → FIRING, pod alive |
| 8 QoS recap | 14:00–15:00 | Seq H | eviction order vs kernel indifference |
| 9 Checklist | 15:00–16:30 | Seq I | 7 lines, full-frame |
| 10 Season wrap | 16:30–17:45 | Seq J | four-episode system diagram |
| 11 Outro | 17:45–18:30 | Text | Season 2 networking tease ("no process listens on a ClusterIP") |

---

## Production Notes

- **Record Phases 4-7 in one sitting** — the Grafana history (bad pod's
  death + sized pod's survival + alert firing) must be continuous for the
  money shot
- Start Grafana recording BEFORE the Phase 2 kill so the bad pod's full
  climb-and-cliff is in the 30m window
- The Prometheus Alerts page (`/alerts`) needs screen time — rehearse the
  `for: 1m` timing once so the FIRING capture isn't dead air
- Thumbnail: the `RESTARTS 4 vs 0` split (Sequence F frame) — instant
  story comprehension
