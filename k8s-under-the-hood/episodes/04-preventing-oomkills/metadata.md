# How do you prevent Kubernetes OOMKills?
## YouTube Metadata

---

## Title Options

### Primary (recommended)

**How to Prevent Kubernetes OOMKills (Right-Sizing, Alerts & QoS — Live Proof)**

### Alternatives

1. **Stop Raising Memory Limits: The Right Way to Prevent OOMKills**
   - Leads with the anti-pattern — instantly relatable.

2. **OOMKill Prevention: From Measured Data to a Firing Alert (Full Demo)**
   - Emphasizes the evidence-driven arc.

3. **"Just Increase the Limit" — Why That's Not a Fix (Kubernetes OOMKills)**
   - Quote-a-real-meeting framing; strong comment-bait title.

4. **Kubernetes Memory Right-Sizing: The Complete Method (p95 → Guaranteed QoS)**
   - The searchable, professional version.

5. **The OOMKill Fix: Same Load, Zero Restarts (Kubernetes Season Finale)**
   - Spoilers the money shot — sometimes that works.

### SEO Notes

- Primary keywords: `kubernetes oomkill prevention`, `kubernetes memory
  right-sizing`, `kubernetes requests vs limits`, `vpa kubernetes`,
  `prometheus memory alert`
- Secondary: `guaranteed qos`, `p95 working set`, `memory limit best
  practices`, `alert before oomkill`
- Primary title is 68 characters — at the display limit.

---

## Thumbnail Concept

### Primary Design

**Layout:** Two terminal cards, mirrored.

**Left card:**
- `RESTARTS: 4` in red, huge
- Below: `128Mi` crossed out

**Right card:**
- `RESTARTS: 0` in green, same size
- Below: `512Mi` with a shield icon

**Center:** "SAME LOAD" in a yellow badge joining both cards

**Bottom banner:** "PREVENTION, PROVEN"

**Overall mood:** before/after proof. The viewer should want to know what
changed between left and right.

### Alternative Concepts

**Concept B — The Math:** `(p95 × headroom)` in big type over a climbing
graph, "SIZE FROM DATA" banner.

**Concept C — The Alert:** Prometheus `FIRING` badge over a pod still
green/running, "PAGE ME BEFORE THE KERNEL DOES".

**Concept D — The Anti-Pattern:** `128Mi → 512Mi` YAML diff with a red ✗
and "6 MINUTES LATER..." caption.

---

## YouTube Description

```
How to Prevent Kubernetes OOMKills (Right-Sizing, Alerts & QoS — Live Proof)

Your pod got OOMKilled. The standup asks "what are we doing so it never happens again?" — and most teams answer with a bigger number: 128Mi becomes 512Mi and everyone moves on. In this season finale we fix an OOMKill-prone pod PROPERLY, and prove it live with the exact same load that killed it.

We cover:
• The fork that decides the fix: leak (fix the app) vs under-sized (fix the platform)
• The anti-pattern, quantified: time-to-limit math — why raising the limit on a leak just reschedules the death to 3am
• Fix A (leaks): the app-level fix, live — watch the working set FALL
• Fix B (right-sizing): p95 from real traffic × headroom → the exact YAML
• requests == limits: Guaranteed QoS as eviction armor (and when the kernel ignores it anyway)
• The safety net: a Prometheus alert that fires at 90% of limit — BEFORE the kernel acts (watched live: FIRING while the pod survives)
• VPA and its two traps (it restarts to apply; it right-sizes you INTO leaks)
• The 7-line prevention checklist (printable, in the repo)

The proof: same pod, same allocate command that killed it in Episode 1 — RESTARTS 4 vs RESTARTS 0. That's the difference between guessing and engineering.

⏱ Timestamps:
0:00  - The question after every post-mortem
1:00  - The fork: leak vs legit (deriv, again)
2:30  - The anti-pattern: "just raise the limit" — the math
4:30  - Fix A: leaks are app bugs (/release, working set falls live)
6:30  - Fix B: right-sizing from p95 + headroom (the YAML)
9:30  - THE PROOF: same load, zero restarts
11:30 - The safety net: alert at 90% — FIRING before the kernel
14:00 - Guaranteed QoS: the last line of defense (and its limits)
15:00 - The 7-line prevention checklist
16:30 - Season 1 wrap: four episodes, one system
17:45 - Season 2 tease: what IS a ClusterIP?

🔗 Season 1 playlist:
Ep 1 — What REALLY Happens When Kubernetes OOMKills a Pod?
Ep 2 — OOMKilled vs Evicted: They Are NOT the Same
Ep 3 — How to Diagnose an OOMKilled Pod in 5 Minutes

🔗 Printables in the repo: the Episode 3 runbook + the Episode 4 prevention checklist

🛠 Lab: 3-node K3s on Proxmox, Prometheus + Grafana — one command per episode reproduces everything.

If this was helpful, subscribe for Season 2 — we go under the networking hood next.

#Kubernetes #OOMKilled #RightSizing #SRE #DevOps
```

### Short Description (Shorts / social)

```
"One megabyte per second leak. 128Mi limit buys 2 minutes. 512Mi buys 8. You didn't fix it — you rescheduled it to 3am." Then we fixed it for real: same load, RESTARTS 4 → 0. 📉

Full episode: [link]
#Kubernetes #OOMKilled #SRE
```

---

## Hashtags

### Primary (YouTube description)

```
#Kubernetes #OOMKilled #RightSizing #SRE #DevOps #KubernetesBestPractices #RequestsVsLimits #QoS #Prometheus #Alerting #VPA #MemoryManagement #SiteReliabilityEngineering #PlatformEngineering #K8s
```

### Additional (social promotion)

```
#GuaranteedQoS #Burstable #CapacityPlanning #Observability #Grafana #KubernetesInternals #DevOpsLife #SRELife #LearnKubernetes #TechTutorial #CloudNative
```

---

## Backend Metadata

### Category
Science & Technology → Software Tutorials

### Tags
```
kubernetes, oomkill prevention, kubernetes memory right-sizing, requests vs limits, guaranteed qos, kubernetes alerts, prometheus alert, vpa, vertical pod autoscaler, p95, working set, memory limits best practices, kubernetes tutorial, sre, devops, platform engineering, k3s, prometheus, grafana, capacity planning
```

### Series
Kubernetes Under the Hood — Season 1, Episode 04 (finale)

### Estimated Duration
~18 minutes

### Captions/Subtitles
Full narration → .srt; auto-translate to Spanish, Portuguese, French, German, Hindi

---

*End of Metadata*
