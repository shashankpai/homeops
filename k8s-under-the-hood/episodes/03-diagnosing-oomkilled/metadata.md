# How do you actually diagnose an OOMKilled Pod?
## YouTube Metadata

---

## Title Options

### Primary (recommended)

**How to Diagnose an OOMKilled Pod in 5 Minutes (Kubernetes Runbook)**

### Alternatives

1. **The OOMKill Runbook: Triage to Root Cause in 4 Layers**
   - Emphasizes the ordered methodology.

2. **Pod Dead, Logs Empty — Here's Exactly What to Run Next**
   - Problem-first, targets people mid-incident RIGHT NOW.

3. **OOMKilled vs CrashLoopBackOff: The 30-Second Triage Every SRE Needs**
   - Leads with the fork — the episode's most shareable concept.

4. **Exit Code 137 Decoded: A Field Guide to Dead Kubernetes Pods**
   - The number people google, packaged as a system.

5. **Stop Guessing: A Repeatable OOMKill Investigation (Live Demo)**
   - Anti-instinct framing — appeals to process lovers.

### SEO Notes

- Primary keywords: `kubernetes oomkilled diagnosis`, `oomkilled runbook`,
  `kubernetes exit code 137`, `pod restarted no logs`
- Secondary: `crashloopbackoff vs oomkilled`, `kubectl logs empty`,
  `cgroup memory.events`, `dmesg oom kill`
- Primary title is 61 characters — within display limits.

---

## Thumbnail Concept

### Primary Design

**Layout:** Terminal-styled checklist card.

- Background: dark terminal (#1e1e2e)
- A checklist rendered in monospace, rows highlighted one by one:
  - `✓ kubectl describe  — 137` (green check)
  - `✓ metrics: WS vs limit` (green check)
  - `✓ memory.events: oom_kill=1` (green check)
  - `○ dmesg (only if needed)` (gray, dimmed)
- Header text in yellow: "DEAD POD?"
- Bottom banner: "5-MIN RUNBOOK"

**Overall mood:** competence porn. The viewer should feel "I want to BE
this organized during an incident."

### Alternative Concepts

**Concept B — The Fork:** a decision tree with three branches
(OOMKilled / CrashLoop / Evicted), "WHICH KILLER?" at the top.

**Concept C — Empty Logs:** a terminal showing literally nothing with
a magnifying glass, "LOGS: EMPTY. START HERE."

**Concept D — The Countdown:** a stopwatch + pod tombstone, "5 MINUTES
TO ROOT CAUSE."

---

## YouTube Description

```
How to Diagnose an OOMKilled Pod in 5 Minutes (Kubernetes Runbook)

A pod restarted overnight. The logs are empty. Someone asks "what happened?" in the standup — in five minutes. In this episode we build the runbook the only way it sticks: by using it on a fresh kill, live, with a timer.

The method: triage first (30 seconds tells you WHICH family of death), then investigate exactly one layer deeper than you need — never five.

We cover:
• The 30-second triage: OOMKilled vs CrashLoopBackOff vs Evicted — same symptom, three different killers
• Why empty logs are a HINT, not a dead end (SIGKILL can't be logged)
• Exit code 137 decoded: 128 + 9, and the fork with exactly two branches
• Layer 1 (API): describe + exit code — the "what happened" answer in 10 seconds
• Layer 2 (Metrics): the fix decider — deriv() tells leak vs under-sized vs regression
• Layer 3 (Node): cgroup memory.events — the kernel's signed confession
• Layer 4 (Kernel): dmesg — exhibit A for the post-mortem (and when you're just procrastinating)
• The stop rule: match depth to the question you're answering
• The complete evidence matrix — cost and payoff of every layer

Everything is demonstrated on a 3-node K3s cluster with Prometheus/Grafana. The printable runbook (all commands, ready for your wiki) is linked below.

⏱ Timestamps:
0:00  - The 5-minute standup problem
1:00  - Triage: the 30-second fork (OOMKilled vs CrashLoop vs Evicted)
3:00  - False leads: why logs mislead in BOTH directions
4:30  - Layer 1: the API (describe + exit code 137 decoded)
7:00  - Layer 2: metrics — the fix decider (leak vs under-sized)
9:30  - Layer 3: the node (memory.events — the kernel's confession)
11:30 - Layer 4: dmesg + the STOP rule
13:00 - The evidence matrix (the screenshot)
14:30 - Outro: two-speed diagnosis + the prevention tease

🔗 Episode 1 (the full 5-layer descent): What REALLY Happens When Kubernetes OOMKills a Pod?
🔗 Episode 2 (the eviction runbook): OOMKilled vs Evicted — They Are NOT the Same
🔗 Printable runbook: episodes/03-diagnosing-oomkilled/runbook.md (in the repo)

📋 Commands covered:
kubectl get pods (custom-columns), kubectl logs --previous,
kubectl describe pod, kubectl get -o jsonpath,
deriv() / container_memory_working_set_bytes,
cat /sys/fs/cgroup/.../memory.events, dmesg -T

If this was helpful, subscribe — we go under the hood every time.

#Kubernetes #OOMKilled #SRE #DevOps #Troubleshooting
```

### Short Description (Shorts / social)

```
Pod dead. Logs EMPTY. You have 5 minutes before standup. Here's the exact runbook — triage in 30 seconds, then one layer deeper than you need. Never five. 🕵️

Full episode: [link]
#Kubernetes #OOMKilled #SRE
```

---

## Hashtags

### Primary (YouTube description)

```
#Kubernetes #OOMKilled #SRE #DevOps #KubernetesTroubleshooting #ExitCode137 #CrashLoopBackOff #Linux #Runbook #SiteReliabilityEngineering #ContainerDebugging #K8s #IncidentResponse #Postmortem #LearnKubernetes
```

### Additional (social promotion)

```
#KubernetesInternals #Debugging #OnCall #SRELife #DevOpsLife #Observability #Prometheus #Grafana #Troubleshooting #TechTutorial #PlatformEngineering
```

---

## Backend Metadata

### Category
Science & Technology → Software Tutorials

### Tags
```
kubernetes, oomkilled, oomkilled diagnosis, kubernetes runbook, exit code 137, crashloopbackoff, pod restarted no logs, kubectl logs empty, kubernetes troubleshooting, cgroups, memory.events, dmesg, oom killer, prometheus, deriv, leak detection, sre, devops, incident response, k8s
```

### Series
Kubernetes Under the Hood — Season 1, Episode 03

### Estimated Duration
~16 minutes

### Captions/Subtitles
Full narration → .srt; auto-translate to Spanish, Portuguese, French, German, Hindi

---

*End of Metadata*
