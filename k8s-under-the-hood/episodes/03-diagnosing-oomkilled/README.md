# Episode 3 — How do you actually diagnose an OOMKilled Pod?

> **Status:** Skeleton (planned) · Season 1, Episode 03
> **Predecessors:** [Episode 1 — the 5-layer OOMKill descent](../../README.md) ·
> [Episode 2 — OOMKilled vs Evicted](../02-oomkilled-vs-evicted/lab-guide.md)

## Objective

Turn the investigation techniques from Episodes 1-2 into a **repeatable,
ordered runbook** — the episode a viewer bookmarks for the day it happens
to them. Pure methodology, demonstrated on the same lab.

## Core Content (what we intend to show)

A symptom-driven decision tree, worked live against a fresh kill:

1. **Symptom triage (2 min)** — what `STATUS`/`RESTARTS`/`REASON` tell you
   before you type anything else; OOMKilled vs Evicted vs CrashLoop as
   first fork (Episode 2's table as the sorting hat)
2. **The false leads** — why logs show nothing (SIGKILL), why
   `kubectl logs` misleads, the CrashLoopBackOff confusion
3. **The ordered checklist** — API (`describe`) → exit code decode →
   metrics (`last_terminated_reason`, working set vs limit) → node
   (cgroup `memory.events`) → kernel (`dmesg`) — with a "when to stop"
   criterion at each level
4. **The evidence matrix** — which layer answers which question,
   which commands, what output proves what
5. **Worked incident** — payment-service killed fresh; run the whole
   runbook on camera in real time (~10 min)

## Planned Artifacts (mirroring Episodes 1-2)

- `manifests/` (reuse Episode 1's payment-service)
- `scripts/demo.sh` — scripted kill + guided runbook walk
- `runbook.md` — the printable decision tree + command checklist
  (the episode's takeaway artifact)
- `promql/queries.md` — diagnosis query set
- `narration.md` / `storyboard.md` / `metadata.md`

## Format

~15 min, single continuous worked investigation (no new infrastructure —
pure payoff episode for the lab already built).
