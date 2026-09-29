# OOMKilled vs Evicted — They Are NOT the Same
## Full Visual Storyboard

> **Duration:** ~20 minutes · **Format:** comparison episode, two killers
> **Principle:** every concept appears TWICE — once as OOMKill, once as
> eviction — so the viewer's brain does the contrast work.

---

## Visual Style Guide

(Same conventions as Episode 1)

- **Terminal:** dark theme, large font (18pt+), minimal prompt, commands on
  one line, output trimmed to the informative lines
- **YAML/manifests:** syntax-highlighted, zoomed to the relevant block with
  the REST grayed out
- **Diagrams:** white text on dark background, arrows left-to-right,
  red reserved for killers/death/thresholds, green for healthy/protected
- **Pacing:** terminal typing 1.5–2× speed; pauses on evidence lines
- **Grafana:** browser zoomed to hide chrome, 5s refresh, cursor arrow
  on the moment of crossing

---

## Key Visual Sequences

### Sequence A — The Two Corpses (hook, 0:00–1:00)

```
SPLIT SCREEN
┌─────────────────────────────┬─────────────────────────────┐
│ kubectl get pods -n shopnow │ kubectl get pods -n          │
│                             │   eviction-demo              │
│ STATUS: Running             │ STATUS: Evicted              │
│ RESTARTS: 3                 │ RESTARTS: —                  │
│                             │                              │
│ (still here, restarting)    │ (gone — new pod elsewhere)   │
└─────────────────────────────┴─────────────────────────────┘
        "Two deaths. Same night. Two different killers."
```

- Two terminals side by side, both scrolled to the status columns
- Freeze frame + red circles: `RESTARTS: 3` vs `Evicted`

### Sequence B — The Two Actors (theory, 1:00–3:30)

```
        KERNEL                          KUBELET
   (per-container)                    (per-node)
        │                                │
  watches cgroup                watches memory.available
  memory.max = 128Mi            threshold: <1Gi (configured)
        │                                │
   kills PROCESS                 deletes PODS
   exit code 137                 by QoS ranking
        │                                │
   BestEffort? irrelevant    BestEffort dies FIRST
```

- Build the two columns in sync, one row at a time
- Final beat: "two killers, two scopes, two different crime scenes"

### Sequence C — The Manifest With Nothing In It (setup, 4:00)

```yaml
# BestEffort QoS: NO resources block at all.
# No requests to protect it, no limits to kill it
```

- Show a normal manifest WITH resources first (payment-service),
  then the hog manifest — the resources block is literally absent
- Slow zoom + highlight on the empty space where resources would be
- "The kernel will never kill these. There's no limit to cross."

### Sequence D — The Drain (trigger, 6:00–8:00)

- Grafana Panel 1 full-screen: blue `node_memory_MemAvailable_bytes`
  falling, red dashed threshold line at 1Gi
- Time-lapse the 2–3 min ramp into ~20 s of screen time
- Side-by-side inset: Episode 1's cliff (working set climbing to limit)
  vs today's drain (available falling to threshold) — same shape,
  opposite direction, labeled "MIRROR IMAGES"

### Sequence E — The Eviction + The One-Line Confession (8:00–10:00)

```
kubectl get pods -n eviction-demo -w
memory-hog-...-7tq1   0/1   Evicted   0   9m
```

- Freeze on `Evicted` — hold 3 seconds
- Then the event, full screen:

```
The node was low on resource: memory.
Threshold quantity: 1Gi, available: 998Mi.
```

- Read it aloud while each phrase highlights in sequence:
  THE NODE → MEMORY → 1Gi → 998Mi
- "It names the killer, the weapon, the threshold, and the evidence in one line."

### Sequence F — The Metrics Replay (observability, 10:00–12:30)

Screen-recorded during the trigger phase, replayed with narration:
1. Panel 1: the crossing (drain hits red line) — the cliff moment
2. Panel 2: MemoryPressure flipping 0→1 at the crossing
3. Panel 3: three hog lines stepping to Evicted, one at a time —
   "no restart counter climbing — evicted pods don't restart, they get replaced"
4. Panel 4 QoS lens: eviction-demo climbing with no ceiling vs
   shopnow flat — "one died entirely, the other didn't even notice"

### Sequence G — The Ranking Ladder (8/12:30–15:00)

```
   ┌──────────────┐  dies first
   │ BestEffort   │  ← the hogs (no requests)
   ├──────────────┤
   │ Burstable    │  ← usage OVER requests (payment-service: -34MB → safe)
   ├──────────────┤
   │ Guaranteed   │  ← protected
   └──────────────┘  dies last
        PriorityClass = tiebreaker
```

- Animate: pods placed on the ladder as introduced
- Highlight the payment-service math: usage 30MB − request 64Mi = NEGATIVE
- Final contrast flash: "Kernel: QoS irrelevant. Kubelet: QoS is everything."

### Sequence H — Two Logs, Two Authors (node, 15:00–17:00)

```
EPISODE 1                    EPISODE 2
dmesg                        journalctl -u k3s-agent
"Out of memory:              "eviction manager:
 Killed process"              Successfully evicted pod"
   KERNEL'S LOG                 KUBELET'S LOG
```

- Split terminal, both logs scrolled to the confession lines
- "The killer's identity determines where the evidence lives."
- This is the takeaway screenshot #2

### Sequence I — The Comparison Table (money shot, 17:00–18:30)

- Both corpses fresh in two terminals (restarts=4 Running vs Evicted)
- Then the full table (8 rows) full-frame, built row by row
- "Every row is a clue you collected live. Screenshot it."

---

## Section-by-Section Storyboard

| Phase | Time | Visuals | Action |
|---|---|---|---|
| 1 Hook | 0:00–1:00 | Seq A | Two terminals, two corpses, freeze frames |
| 2 Theory | 1:00–3:30 | Seq B | Two-actor diagram, eviction signals, defaults |
| 3 Setup | 3:30–5:00 | Seq C + terminal | Deploy, manifest with nothing in it, threshold config |
| 4 Baseline | 5:00–6:00 | Terminal + Grafana | Conditions: False, the gap above the red line |
| 5 Trigger | 6:00–8:00 | Seq D | Time-lapse drain, mirror-image inset |
| 6 Eviction | 8:00–10:00 | Seq E | -w output, freeze on Evicted, the one-line event |
| 7 Metrics | 10:00–12:30 | Seq F | Grafana replay: crossing, condition flip, reasons, QoS lens |
| 8 Ranking | 12:30–15:00 | Seq G | The ladder, the negative math, the QoS asymmetry |
| 9 Node | 15:00–17:00 | Seq H | config.yaml, journalctl, two-logs split |
| 10 Table | 17:00–18:30 | Seq I | Fresh corpses + table row build |
| 11 Outro | 18:30–20:00 | Text bullets | Two weapon lists, cleanup full circle, next-ep tease |

---

## Production Notes

- **Record the Grafana drain live during the trigger phase** (Sequence F
  source material) — 5s refresh, ~20 min wall time, time-lapse in edit
- The eviction moment itself is not instant (kubelet housekeeping) —
  use the -w output, edit the wait out
- Keep payment-service's Grafana line visible during the drain — its
  flatness is the QoS payoff
- Emergency cutaway if the node destabilizes: cleanup.sh output restoring
  MemoryPressure to False
- Thumbnail concept (see metadata.md): split `RESTARTS: 3` vs `Evicted`
  with "TWO KILLERS" — mirrors the episode's core image
