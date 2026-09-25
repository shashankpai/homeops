# Episode 01: Demo Flow Mapping
## Narration Phase → Lab-Guide Section Mapping

This document maps each narration phase to the corresponding lab-guide sections that should be displayed on screen during the video.

| Narration Phase | Time | Lab-Guide Sections | What to Show | Notes |
|---|---|---|---|---|
| **Phase 1: Intro / Hook** | 0:00–1:30 | — | Title card; fake "morning after" pod state | Hook the viewer with the mystery |
| **Phase 2: What Is a Memory Limit?** | 1:30–4:00 | 1–3 (overview, objectives, architecture) | VS-3 chain diagram: YAML → kubelet → containerd → cgroup | Conceptual, no commands |
| **Phase 3: Deploy the Workload** | 4:00–6:00 | 5 | `kubectl apply`, `kubectl wait`, record Pod/Node | First live commands |
| **Phase 4: Baseline** | 6:00–8:00 | 6 | `kubectl get pod`, `/usage`, `cat memory.max`, Grafana open | Establish healthy state |
| **Phase 5: Trigger the OOMKill** | 8:00–10:00 | 7 | `/allocate?mb=200`, `kubectl get pods -w`, split with Grafana | The kill — visual centerpiece |
| **Phase 6: Layer 1 — Kubernetes API** | 10:00–12:30 | 8 | `kubectl describe pod`, jsonpath lastState | After-action report |
| **Phase 7: Decode 137** | 12:30–14:00 | 9 | 137 = 128 + 9 graphic | No commands — concept |
| **Phase 8: Layer 2 — Container Runtime** | 14:00–16:00 | 10 | SSH to node, `crictl ps -a`, `crictl inspect` | First node-level commands |
| **Phase 9: Layer 3 — Cgroups** | 16:00–19:00 | 11 | Find cgroup, `cat memory.max/current/events` | Smoking gun (oom_kill) |
| **Phase 10: Layer 4 — Kernel** | 19:00–22:00 | 12 | `dmesg -T \| grep -i "out of memory"`, chain diagram, two-killers side path | The executioner's log |
| **Phase 11: Layer 5 — Metrics** | 22:00–25:00 | 13 | Port-forward, 3 PromQL queries, Grafana dashboard tour | The historical record |
| **Phase 12: Working Set vs RSS** | 25:00–27:00 | 14 | 3-tier memory graphic | Conceptual |
| **Phase 13: QoS Classes** | 27:00–28:30 | 15 | QoS table + cgroup-kill nuance | Conceptual, Episode 2 teaser |
| **Phase 14: Troubleshooting Checklist** | 28:30–30:00 | 16 | 6-step checklist + 3 graph shapes | Summary diagram |
| **Phase 15: Prevention** | 30:00–32:00 | 17 | Best-practice cards | Conceptual |
| **Phase 16: Cleanup / Outro** | 32:00–33:00 | 18 | `kubectl delete namespace shopnow`, recap | End screen |

## Key Demo Sections

### Deploy Phase (Phase 3)
- **Lab sections:** 5 (deploy the demo workload)
- **Duration:** ~2 minutes of screen time
- **Key commands:** `kubectl apply`, `kubectl wait`, `kubectl get ... -o jsonpath`
- **Expected output:** 4 objects created; pod Ready; Pod name + Node name recorded

### Baseline Phase (Phase 4)
- **Lab sections:** 6 (baseline)
- **Duration:** ~2 minutes of screen time
- **Key commands:** `kubectl get pod`, `python -c urllib /usage` (no curl in image), `cat /sys/fs/cgroup/memory.max`
- **Expected output:** Running / 0 restarts; rss ≈ 18 MB; memory.max = 134217728
- **Gotcha for recording:** the memory.max value must match the Phase 2 diagram (same number on screen 3 times by now)

### Kill Phase (Phase 5) ← **Visual Centerpiece**
- **Lab sections:** 7 (trigger)
- **Duration:** ~2 minutes of screen time
- **Key commands:** `python -c urllib POST /allocate?mb=200` (image has no curl), `kubectl get pods -w`
- **Expected output:** "allocating 200MB in 2MB steps..."; restarts 0→1 after ~90-110s of gradual climb; Grafana shows the cliff live
- **Recording notes:** split-screen terminal + Grafana; 60fps; the restart tick is the moment — don't cut away early

### Layer 1–2 (Phases 6, 8)
- **Lab sections:** 8 (kubectl) + 10 (crictl)
- **Duration:** ~4.5 minutes of screen time
- **Key commands:** `kubectl describe`, jsonpath, `ssh`, `crictl ps -a`, `crictl inspect`
- **Expected output:** Last State OOMKilled/137 from both API and runtime

### Layer 3 (Phase 9) ← **Smoking Gun**
- **Lab sections:** 11 (cgroups)
- **Duration:** ~3 minutes of screen time
- **Key commands:** cgroup discovery, `cat memory.max`, `memory.current`, `memory.events`
- **Expected output:** oom_kill: 1 in memory.events — red highlight moment

### Layer 4 (Phase 10) ← **The Confession**
- **Lab sections:** 12 (kernel)
- **Duration:** ~3 minutes of screen time
- **Key commands:** `dmesg -T | grep -i -A5 "out of memory"`
- **Expected output:** "Out of memory: Killed process NNNNN (python)" — zoom on the process name

### Layer 5 (Phase 11)
- **Lab sections:** 13 (metrics)
- **Duration:** ~3 minutes of screen time
- **Key commands:** `kubectl port-forward`, 3 PromQL queries
- **Expected output:** sawtooth graph, OOMKilled flag → 1, oom_events_total spike

### Cleanup (Phase 16)
- **Lab sections:** 18 (cleanup)
- **Duration:** ~1 minute of screen time
- **Key commands:** `kubectl delete namespace shopnow` (or `make cleanup-ep01`)
- **Expected output:** namespace deleted; monitoring untouched

## Notes for Video Production

### Narration vs Lab-Guide
1. **Narration is conversational** — it doesn't mention every command. Use the lab-guide as the authoritative source for what to run.
2. **Lab-guide has "Why we run it" notes** — use these for on-screen text or voiceover asides.
3. **Expected outputs are in the lab-guide** — match these when recording to ensure accuracy.

### Demo Pacing
- **Total runtime:** ~33 minutes
- **Setup + baseline:** ~4 min (Phases 3–4)
- **The kill:** ~2 min (Phase 5)
- **5-layer investigation:** ~12 min (Phases 6–11) — the heart of the episode
- **Concepts:** ~3.5 min (Phases 12–13)
- **Checklist + prevention:** ~3.5 min (Phases 14–15)
- **Cleanup + outro:** ~1 min (Phase 16)

### One-Command Alternative
Everything in Phases 3–11 is automated by `episodes/01-oom-killed/scripts/demo.sh` (with pause points). For recording, run the manual lab-guide commands for full control; use `make demo-ep01` for a dry run or to verify the lab before recording.

### Syncing Narration & Lab-Guide
If you update the narration timestamps, update this table accordingly. The lab-guide sections should remain stable — they're the "source of truth" for what commands to run.

## Quick Reference: Where Each Artifact Is Used

| Artifact | Used in |
|---|---|
| `manifests/payment-service.yaml` | Phase 3 (deploy) |
| `scripts/demo.sh` | Dry run / verification before recording |
| `scripts/cleanup.sh` | Phase 16 (or `make cleanup-ep01`) |
| `promql/queries.md` | Phase 11 (metrics) |
| `dashboards/oom-investigation.json` | Phases 4, 5, 11 (Grafana) |
| `lab-guide.md` | The authoritative runbook for every phase |
