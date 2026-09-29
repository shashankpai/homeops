# OOMKilled vs Evicted — They Are NOT the Same
## YouTube Metadata

---

## Title Options

### Primary (recommended)

**OOMKilled vs Evicted: They Are NOT the Same (2 Killers, 1 Cluster)**

### Alternatives

1. **Kubernetes Eviction Explained: When the Kubelet Kills Your Pods**
   - Leads with the less-understood half of the pair.

2. **Pod Evicted? Here's Who Killed It (It Wasn't the Kernel)**
   - Problem-first framing for people debugging RIGHT NOW.

3. **OOMKilled vs Evicted: The Difference That Matters in an Incident**
   - Targets the incident-response use case directly.

4. **Kubernetes QoS Classes Decide Who Dies First (Eviction, Explained Live)**
   - Leans on the QoS ranking — the episode's big aha.

5. **Why Kubernetes Deletes Pods Under Memory Pressure (Live Eviction Demo)**
   - Search-friendly: "kubernetes pod evicted memory pressure".

6. **Two Ways Your Pod Dies: Kernel OOMKill vs Kubelet Eviction**
   - Clean comparative framing.

### SEO Notes

- Primary keywords: `kubernetes pod evicted`, `oomkilled vs evicted`,
  `kubernetes eviction`, `kubernetes qos classes`, `memory pressure`
- Secondary: `kubelet`, `besteffort`, `burstable`, `guaranteed`,
  `eviction threshold`, `kubectl describe node`
- Primary title is 64 characters — within the ~70-char display limit.

---

## Thumbnail Concept

### Primary Design

**Layout:** Split screen, two "case files."

**Left side (50%):**
- Terminal-styled box: `RESTARTS: 3` in yellow, pod status `Running`
- Caption below in white: "OOMKILLED — kernel"
- Small red SIGKILL stamp in the corner

**Right side (50%):**
- Terminal-styled box: `STATUS: Evicted` in red, `RESTARTS: —`
- Caption below in white: "EVICTED — kubelet"
- Small red trash-can/X icon in the corner

**Center divider:** a vertical "VS" badge (yellow, bold)

**Top banner:** "TWO KILLERS. ONE CLUSTER." — white on semi-transparent dark strip

**Overall mood:** Case-file comparison. The viewer should immediately
want to know what the difference is.

### Alternative Concepts

**Concept B — The Drain:**
- Simplified graph: blue line falling to a red threshold line
- At the crossing, a pod icon shattering
- Text: "The moment the kubelet kills"

**Concept C — The Ladder:**
- Three rungs labeled Guaranteed / Burstable / BestEffort
- BestEffort rung broken, pod falling
- Text: "Who dies first?"

**Concept D — The Split Corpse:**
- Left: pod icon with bandages, "restarted ×3"
- Right: empty outline where a pod was, "deleted"
- Text: "Same cluster. Different killers."

### Text Guidelines

- 3–5 words max on the thumbnail itself
- High contrast: white/yellow on dark terminal backgrounds
- Bold sans-serif (Inter Bold / Montserrat)
- The `Evicted` status is the focal point — it's the newer, lesser-known death

---

## YouTube Description

```
OOMKilled vs Evicted: They Are NOT the Same (2 Killers, 1 Cluster)

Two pods died last night. One restarted 3 times. The other just vanished. Same cluster — two different killers: the Linux kernel (per-container OOM kill) and the kubelet (node-level eviction). In this episode we trigger BOTH, live, and contrast every layer.

We cover:
• The four kubelet eviction signals (memory, nodefs, imagefs, pid)
• Hard vs soft eviction thresholds — and where they're configured
• Why evicted pods DON'T restart in place (Failed + rescheduled, vs OOMKilled's RESTARTS +1)
• The eviction ranking: BestEffort dies first, Guaranteed is protected
• Usage-over-requests — the ranking metric nobody tells you about
• QoS asymmetry: the kernel ignores QoS entirely, the kubelet depends on it
• Node conditions (MemoryPressure) and why the scheduler avoids pressured nodes
• kubelet's journalctl confession vs the kernel's dmesg confession
• The complete side-by-side: killer, scope, trigger, evidence, metrics

Everything is demonstrated live on a 3-node K3s cluster on Proxmox. We fill a real worker node's memory with BestEffort "memory hog" pods until the eviction threshold trips — and watch it happen in Grafana.

⏱ Timestamps:
0:00  - Two corpses, one cluster
1:00  - The two actors: kernel vs kubelet (eviction signals + thresholds)
3:30  - Setup: BestEffort hogs + the threshold config
5:00  - Baseline: node healthy, the gap above the red line
6:00  - TRIGGERING THE EVICTION (live drain in Grafana)
8:00  - The eviction: STATUS Evicted + the one-line confession event
10:00 - Metrics replay: drain, MemoryPressure flip, eviction cascade
12:30 - The ranking: who dies first and why (QoS ladder)
15:00 - On the node: two logs, two authors
17:00 - THE COMPARISON TABLE (both deaths, side by side)
18:30 - Prevention: two different weapon lists

🔗 Episode 1 (the OOMKill descent, 5 layers):
What REALLY Happens When Kubernetes OOMKills a Pod

🔗 Next episode:
Episode 3 — How do you actually diagnose a dead pod? (the runbook)

🛠 Lab environment:
- 3-node K3s cluster on Proxmox VMs
- Prometheus + Grafana + node-exporter + kube-state-metrics
- All manifests, scripts, and the dashboard JSON in the repo

📋 Commands covered:
kubectl get pods -w, kubectl describe pod/node, kubectl get events,
kubectl top node, kubectl custom-columns (qosClass), journalctl -u k3s-agent,
cat /etc/rancher/k3s/config.yaml

If this was helpful, subscribe — we go under the hood every time.

#Kubernetes #Eviction #OOMKilled #SRE #DevOps
```

### Short Description (Shorts / social)

```
One pod restarted 3 times. The other just vanished. Same cluster, two different killers: the kernel and the kubelet. We trigger BOTH live and put the corpses side by side. 🕵️‍♂️

Full episode: [link]
#Kubernetes #Eviction #DevOps #SRE
```

---

## Hashtags

### Primary (YouTube description)

```
#Kubernetes #Eviction #OOMKilled #Linux #SRE #DevOps #KubernetesTroubleshooting #QoS #MemoryPressure #Kubelet #K3s #Prometheus #Grafana #SiteReliabilityEngineering #ContainerDebugging
```

### Additional (social promotion)

```
#KubernetesInternals #BestEffort #Burstable #Guaranteed #OOMKiller #NodePressure #PlatformEngineering #CloudNative #Observability #DevOpsLife #SRELife #LearnKubernetes #TechTutorial #Debugging
```

### Strategy

| Category | Hashtags | Purpose |
|----------|----------|---------|
| Core topic | `#Kubernetes #Eviction #OOMKilled` | Primary search |
| The contrast | `#OOMKilled #QoS #MemoryPressure` | Episode-specific |
| Audience | `#SRE #DevOps #PlatformEngineering` | Audience reach |
| Tools | `#K3s #Prometheus #Grafana` | Stack discovery |

---

## Backend Metadata

### Category
Science & Technology → Software Tutorials

### Tags
```
kubernetes, pod evicted, oomkilled vs evicted, kubernetes eviction, eviction threshold, kubelet, memory pressure, qos classes, besteffort, burstable, guaranteed, usage over requests, node conditions, memorypressure, kubernetes troubleshooting, k3s, prometheus, grafana, sre, devops
```

### Series
Kubernetes Under the Hood — Season 1, Episode 02

### Estimated Duration
~20 minutes

### Captions/Subtitles
Full narration → .srt; auto-translate to Spanish, Portuguese, French, German, Hindi

---

*End of Metadata*
