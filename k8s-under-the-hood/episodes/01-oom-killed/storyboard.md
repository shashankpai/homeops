# What REALLY Happens When Kubernetes OOMKills a Pod?
## Full Visual Storyboard

> **Format:** For every major section — timestamp, spoken narration cue, terminal command, expected output, visual/animation suggestion, and on-screen text.
> **Designed for:** 16:9 YouTube technical video (not a corporate slide deck).

---

## Visual Style Guide

- **Terminal:** Dark background (#1e1e2e), monospace font (JetBrains Mono or Fira Code), syntax highlighting where possible.
- **Diagrams:** Clean ASCII-style or flat-design vector graphics on dark background. Accent colors: green for healthy, yellow for warning, red for danger, blue for concepts.
- **On-screen text:** Minimal, high-contrast, sans-serif (Inter or similar). Key takeaways only — never duplicate the full narration.
- **Transitions:** Simple cuts or quick fades. No flashy effects. This is a technical video, not a vlog.
- **Pacing:** Let terminal commands and output breathe. Don't rush past evidence — the viewer needs time to read the output.
- **Signature motif:** The "5-layer descent" — each layer gets a brief full-screen layer-title card (Layer 1/5, 2/5, ...) with a subtle downward motion, reinforcing the journey INTO the machine.

---

## Key Visual Sequences

These 5 visual sequences appear multiple times throughout the episode. They are the core visual vocabulary.

### Visual Sequence 1: The Memory Cliff

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   128Mi ────────────────────────────────── limit        │
│    ▲                                                   │
│    │            working set                             │
│    │               ╱╲                                   │
│    │              ╱  ╲        ╱── new container         │
│    │         ╱╲ ╱    ╲      ╱                           │
│    │        ╱  ▼       ╲    ╱                            │
│    │   ╱╲ ╱    KILL     ╲ ╱                             │
│    │  ╱  ▼       ✝       ▼                              │
│    │ ╱  baseline         restart low                    │
│    │╱                                                    │
│   ───────────────────────────────────────────► time     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Animation:** The working-set line climbs, touches the red limit line, and DROPS vertically (mark the drop with a red flash + "SIGKILL" label). Then a fresh line starts low. The sawtooth repeats if triggered again.

---

### Visual Sequence 2: The 5-Layer Descent

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   LAYER 1 — KUBERNETES API      kubectl   "the report"  │
│              ↓                                          │
│   LAYER 2 — CONTAINER RUNTIME   crictl    "the parent"  │
│              ↓                                          │
│   LAYER 3 — CGROUPS             memory.*  "the rule"   │
│              ↓                                          │
│   LAYER 4 — KERNEL              dmesg     "the killer" │
│              ↓                                          │
│   LAYER 5 — METRICS             PromQL    "the record"  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Animation:** Used as a recurring anchor. At each layer transition, the descent diagram reappears with the current layer highlighted and the layers above dimmed. Camera "descends" one step at a time.

---

### Visual Sequence 3: Where the Limit Lives

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   deployment.yaml                                       │
│     limits.memory: 128Mi                                │
│          │                                              │
│          │  kubelet: "start container, limit 128Mi"     │
│          ▼                                              │
│   containerd (on the NODE)                              │
│          │                                              │
│          │  creates cgroup, writes:                     │
│          ▼                                              │
│   /sys/fs/cgroup/.../memory.max = 134217728             │
│          │                                              │
│          │  ...and walks away.                          │
│          ▼                                              │
│   (kernel enforces from here on)                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Animation:** The YAML value "128Mi" visually transforms into "134217728" as it travels down the chain and lands in the cgroup file. End with the kernel icon glowing — "the kernel is now watching."

---

### Visual Sequence 4: Exit Code Decoder

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│        137  =  128  +  9                                │
│                 │       │                               │
│                 │       └── signal 9 = SIGKILL           │
│                 │           (cannot be caught/blocked)   │
│                 └── "killed by a signal"                 │
│                                                         │
│   Empty logs + exit 137 = SIGKILL fingerprint           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Animation:** The number 137 splits apart into 128 and 9 with a satisfying mechanical motion. The 9 lands on a red "SIGKILL" stamp.

---

### Visual Sequence 5: The Sawtooth

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   working set                                           │
│      ╱╲    ╱╲    ╱╲                                     │
│     ╱  ╲  ╱  ▼  ╱  ▼      ← climb, cliff, restart      │
│  ╱╱    ▼╱     ╲╱                                        │
│ ───────────────────────────────► time                  │
│                                                         │
│   "If you ever see this shape in production,            │
│    you already know what it is."                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Animation:** Used in Phase 5 (live, via Grafana) and Phase 11 (drawn). The line climbs and falls repeatedly like a heartbeat going flat, each drop stamped with restart count +1.

---

## Section-by-Section Storyboard

### Phase 1 — Intro / Hook (0:00–1:30)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 0:00 | "Your pod restarted last night..." | Terminal: `kubectl get pods` with RESTARTS climbing | VS-1 sawtooth faint in background |
| 0:10 | "the logs show nothing" | Terminal: `kubectl logs` → empty output. Hold the empty screen — the emptiness IS the point | — |
| 0:24 | "you do what everyone does first" | `kubectl describe pod` typed live | — |
| 0:40 | "WHO actually killed this container?" | Zoom on OOMKilled/137 lines | Red circle annotation |
| 1:00 | "five layers..." | VS-2 full descent diagram, slow reveal of all 5 layers | Downward motion into the stack |
| 1:15 | "let's go find the killer" | Title card: episode title + cluster arch thumbnail | — |

---

### Phase 2 — What Is a Memory Limit? (1:30–4:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 1:30 | "people think Kubernetes enforces limits. It doesn't." | On-screen text: "Kubernetes does NOT enforce memory limits" | Bold claim card |
| 1:50 | "here's what you write" | YAML editor: resources block | Highlight requests vs limits in different colors |
| 2:00 | "REQUEST — for the scheduler" | Scheduler picking a node (simple diagram) | Blue |
| 2:28 | "watch what happens at container start" | **VS-3: Where the Limit Lives** | Full animation |
| 2:45 | "...and walks away" | The chain diagram ends; kernel icon glows | — |
| 3:05 | "What is a cgroup?" | Cgroup concept box: processes grouped + rule applied | Blue concept |
| 3:30 | "QoS classes" | 3-row table: Guaranteed / Burstable / BestEffort | Green/yellow/gray rows |
| 3:50 | "let's deploy a victim" | — | — |

---

### Phase 3 — Deploy the Workload (4:00–6:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 4:00 | "ShopNow Payment Service... one special power" | Small app diagram: HTTP endpoints listed | `/allocate?mb=N` highlighted red |
| 4:20 | `kubectl apply -f ...` | Terminal: apply output (4 created) | — |
| 4:35 | "requests 64, limits 128" | Manifest excerpt with resources highlighted | Match VS-3 colors |
| 4:58 | "note which node it landed on" | Terminal: wait + echo Pod/Node | Node name boxed — "remember this" |

---

### Phase 4 — Baseline (6:00–8:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 6:05 | `kubectl get pod` | Terminal: 1/1 Running, 0 restarts | Green |
| 6:18 | "what's it using?" | Terminal: `/usage` → rss_mb=18.4 | — |
| 6:45 | "we can read that file FROM INSIDE" | Terminal: `cat /sys/fs/cgroup/memory.max` → 134217728 | Zoom on the number; VS-3 flashback (same number!) |
| 6:58 | "128 × 1024 × 1024" | Calculator overlay: 134217728 = 128Mi | — |
| 7:25 | "open the dashboard" | Grafana: Working Set vs Limit panel, big gap | Green healthy state |

---

### Phase 5 — Trigger the OOMKill (8:00–10:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 8:00 | "200 megabytes on a 128 limit" | Terminal: `/allocate?mb=200` typed slowly — dramatic | — |
| 8:22 | "your classic production memory leak" | — | — |
| 8:48 | `kubectl get pods -w` | Split screen: terminal watch LEFT, Grafana cliff RIGHT | **VS-1: The Memory Cliff, LIVE** |
| 9:00 | "there it goes" | Working set hits limit line; RESTARTS 0→1 | Red flash at the drop; "SIGKILL" stamp |
| 9:32 | "climb, cliff, restart" | Grafana replay of the sawtooth | **VS-5: The Sawtooth** |
| 9:55 | "who killed it? Layer one" | **VS-2** descent, Layer 1 highlighted | — |

---

### Phase 6 — Layer 1: Kubernetes API (10:00–12:30)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 10:00 | "an after-action report" | Layer card: "LAYER 1/5 — KUBERNETES API" | VS-2 highlight |
| 10:10 | `kubectl describe pod` | Terminal: describe output, Last State block | Zoom + red circle on OOMKilled/137 |
| 10:50 | jsonpath command | Terminal: structured JSON | — |
| 11:15 | "no killedBy field" | The JSON with a blank where you'd expect a culprit | Question mark |
| 11:35 | "police report, not the killer" | Analogy graphic: police report icon vs crime scene icon | — |
| 12:00 | "a number we haven't decoded" | "137" large on screen | Transition to VS-4 |

---

### Phase 7 — Decode 137 (12:30–14:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 12:45 | "exit codes have a grammar" | Rule card: "≥128 = killed by signal; signal = code − 128" | — |
| 13:00 | "137 = 128 + 9" | **VS-4: Exit Code Decoder** | Full animation |
| 13:15 | "SIGKILL... between two instructions" | Process timeline: two instructions, X between them — no chance to log | Red X |
| 13:40 | "empty logs + 137 = SIGKILL fingerprint" | Summary card | — |

---

### Phase 8 — Layer 2: Container Runtime (14:00–16:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 14:00 | "everything below this line is ON THE NODE" | `ssh $NODE` + node diagram | VS-2, Layer 2 highlighted |
| 14:35 | "crictl" | Terminal: `crictl ps -a` — two containers, one Exited | Dead/replacement containers labeled |
| 15:20 | `crictl inspect` | Terminal: exitCode 137, reason OOMKilled | Same evidence, closer to metal |
| 16:05 | "runtime GCs dead containers fast" | Caveat card | — |

---

### Phase 9 — Layer 3: Cgroups (16:00–19:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 16:00 | "a magic filesystem the kernel exposes" | `/sys/fs/cgroup` tree visual | VS-2, Layer 3 highlighted |
| 16:20 | find the cgroup | Terminal: derive slice from pod UID (`kubepods-burstable-pod<uid>.slice`) | — |
| 16:48 | "three files tell the entire story" | Terminal: cat max/current/events | Each file zoomed in turn |
| 17:20 | "memory.max — your YAML as a kernel rule" | Flashback VS-3: same number, third appearance | — |
| 17:40 | "memory.current — the NEW container" | Note: low because restarted | — |
| 17:55 | "burn this into memory: memory.events" | Zoom: `oom 1`, `oom_kill 4` | **Red highlight — smoking gun card** |
| 18:45 | "the kernel's own counter" | Card: "NO interpretation needed" | — |

---

### Phase 10 — Layer 4: Kernel (19:00–22:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 19:00 | "the kernel writes its own confession" | VS-2, Layer 4 highlighted | — |
| 19:15 | `dmesg -T | grep -i "out of memory"` | Terminal: OOM killer lines | Line-by-line zoom |
| 19:40 | "THE KERNEL. NAMED. THE PROCESS." | Zoom: "Killed process 18734 (python)" | Big red text treatment |
| 20:20 | "let's assemble the full chain" | **9-step chain diagram** (from narration Phase 10) | Animated sequence, each step lighting up |
| 21:40 | "TWO OOM killers" | Split: cgroup killer vs node killer | "Episode 2" teaser stamp |
| 22:00 | "one more layer" | VS-2, Layer 5 highlighted | — |

---

### Phase 11 — Layer 5: Metrics (22:00–25:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 22:15 | port-forward | Terminal: port-forward + browser opens | — |
| 22:35 | "the cliff" | Prometheus graph: working set vs limit | **VS-1 recreated from real data** |
| 23:20 | "the Kubernetes verdict, as a metric" | `last_terminated_reason{reason="OOMKilled"}` → flips to 1 | — |
| 23:50 | "the kernel's own counter, from Grafana" | `container_oom_events_total` query | Tie-back to Layer 3 smoking gun |
| 24:20 | "the dashboard IS this episode" | Grafana: 5-panel episode dashboard | Full-screen tour |
| 24:40 | "the trend BEFORE the kill" | Graph with 90% warning zone highlighted | Yellow zone |

---

### Phase 12 — Working Set vs RSS (25:00–27:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 25:10 | "WHICH memory number counts?" | **VS graphic:** Virtual / RSS / Working set, 3 tiers | Only "working set" in green |
| 25:55 | "the reclaim dance" | Kernel reclaiming file cache animation | Cache shrinking to stay under limit |
| 26:20 | "the number on trial" | Card: "container_memory_working_set_bytes" | — |

---

### Phase 13 — QoS (27:00–28:30)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 27:10 | QoS table | Guaranteed / Burstable / BestEffort | Priority arrows |
| 27:40 | "QoS does NOT protect you from a cgroup kill" | Guaranteed pod hitting its own limit → dead anyway | Red X over QoS shield |
| 28:05 | "different killers, different rules" | Two-column: cgroup kill vs node kill | Episode 2 teaser |

---

### Phase 14 — Checklist (28:30–30:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 28:38 | 6-step checklist | Full-screen checklist, each step appearing as narrated | — |
| 29:20 | "the SHAPE of the graph tells you the fix" | 3 mini-graphs: leak (climb) / sawtooth (limit low) / spike (load) | Each labeled with its fix |

---

### Phase 15 — Prevention (30:00–32:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 30:06 | rules 1–6 | Cards appearing one at a time, numbered | — |
| 31:25 | "don't cargo-cult it" | Warning card on omitting limits | "Episode 4" teaser stamp |

---

### Phase 16 — Cleanup / Outro (32:00–33:00)

| Time | Narration cue | On screen | Visual |
|---|---|---|---|
| 32:05 | `kubectl delete namespace shopnow` | Terminal: deleted | — |
| 32:20 | "close the case one final time" | **VS-2 final**: all 5 layers lit, each with its verdict ("the report" / "the parent" / "the rule" / "the killer" / "the record") | Full animation, slow |
| 32:45 | "the kernel did the rest" | Card: "Kubernetes wrote a number. The kernel did the rest." | — |
| 32:55 | "Next episode: OOMKilled vs Evicted" | Episode 2 teaser card | Subscribe end screen |

---

## Production Notes

- The **memory.max = 134217728** number should appear on screen at least 4 times (VS-3, Phase 4 baseline, Phase 9, chain diagram) — repetition cements that the YAML, the cgroup file, and the evidence are the SAME number.
- The **descent motif (VS-2)** is the episode's structural spine — use it at every layer transition.
- Grafana live views are the payoff — make sure the recording captures the working-set drop in real time (record at 60fps, slow-mo the kill moment if needed).
- Terminal output in Phases 8–10 runs on the NODE via SSH — use a distinct terminal color/theme so viewers feel the context switch from cluster to node.
