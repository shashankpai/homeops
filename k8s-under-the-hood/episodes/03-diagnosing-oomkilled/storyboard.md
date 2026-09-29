# How do you actually diagnose an OOMKilled Pod?
## Full Visual Storyboard

> **Duration:** ~16 minutes · **Format:** one fresh kill, one runbook
> **Principle:** every layer shown at running-speed, with the STOP rule
> punctuating each one. The runbook table is the recurring visual anchor.

---

## Visual Style Guide

(Same conventions as Episodes 1-2)

- **Terminal:** dark theme, 18pt+, one command per line, output trimmed
- **The runbook table:** recurs as a full-frame visual after each layer —
  rows fill in as phases progress (empty rows → highlighted rows)
- **Timer overlay:** subtle stopwatch in the corner during the worked
  investigation — reinforces the "5 minutes before standup" framing
- **Red = death/kill; green = the stop rule; yellow = decision forks**

---

## Key Visual Sequences

### Sequence A — The Standup Clock (hook)

- Cold open: a clock/standup timer, terminal beside it
- "You have five minutes. Where do you look FIRST?"

### Sequence B — The Triage Fork (1:00–3:00)

```
   kubectl get pods (custom columns)
        │
   ┌────┴─────────────────┬──────────────────────┐
   OOMKilled          CrashLoopBackOff        Evicted
   (kernel/limit)     (the app)               (kubelet/node)
   ↓                      ↓                     ↓
   THIS episode       logs tell you          Episode 2's
                        the answer            runbook
```

- Build the fork live: highlight each branch as the two staged pods match it

### Sequence C — Empty Logs vs Telling Logs (3:00–4:30)

- Split terminal: payment-service logs (nothing) | crashy logs
  ("FAILED: exit 1")
- The money line: "Empty logs are not missing evidence — they ARE evidence."

### Sequence D — Exit Code Decode (5:05)

```
Exit Code 137  =  128 + 9
  128 = killed by a signal
    9 = SIGKILL (uncatchable)
```

- Big-type arithmetic, then the two-branch fork (kernel vs kubelet probe)

### Sequence E — The Fix-Decider Graph (7:00–9:30, observability phase)

- Grafana, Episode 3 dashboard: the autopsy graph (WS vs limit + cliff)
- Then the deriv panel full-screen with the three shapes:
  - linear climb → LEAK
  - plateau → under-sized
  - deploy-step → regression
- "One query, three shapes, three fixes" — the episode's core visual

### Sequence F — The Confession Counter (9:30–11:30)

- Terminal: cgroup path assembly (POD_UID substitution shown as a step)
- `cat memory.events` output with oom_kill highlighted, circled in red
- "A signed confession from the Linux kernel."

### Sequence G — The Stop Rule (12:15)

```
"It OOMKilled"                 → Layer 1
"It's a leak / under-sized"    → Layer 2
"Prove the kernel did it"      → Layer 3
"Exhibit A for the postmortem" → Layer 4
```

- Green highlight; each row appears as narration reads it

### Sequence H — The Full Evidence Matrix (13:05)

- The complete table, full-frame, rows animated filling top-to-bottom
- "This is the screenshot." Hold 5 seconds.

---

## Section-by-Section Storyboard

| Phase | Time | Visuals | Action |
|---|---|---|---|
| 1 Hook | 0:00–1:00 | Seq A | Standup clock framing |
| 2 Triage | 1:00–3:00 | Seq B | Custom-columns fork, two staged pods |
| 3 False leads | 3:00–4:30 | Seq C | Empty vs telling logs, split terminal |
| 4 Layer 1 API | 4:30–7:00 | Seq D | describe output, exit code decode |
| 5 Layer 2 Metrics | 7:00–9:30 | Seq E | Verdict query, autopsy graph, deriv shapes |
| 6 Layer 3 Node | 9:30–11:30 | Seq F | cgroup path build, memory.events |
| 7 Layer 4 + stop rule | 11:30–13:00 | Seq G | dmesg, the stop-rule ladder |
| 8 Evidence matrix | 13:00–14:30 | Seq H | Full table build, "the screenshot" |
| 9 Outro | 14:30–16:00 | Text | Two-speed recap, Episode 4 tease |

---

## Production Notes

- **Record the kill ~4 min before filming the investigation phases** so the
  metrics history (climb + cliff) is fresh in Grafana's 30m window
- The timer overlay is added in edit — don't run a real stopwatch
- The runbook table graphic should match `runbook.md` exactly — same rows,
  same wording (viewers will print that file)
- crashy's backoff timing (10s→20s→40s) is visible in restarts panel —
  let it run during Phase 5 for free background evidence
