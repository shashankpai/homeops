# What REALLY Happens When Kubernetes OOMKills a Pod?
## YouTube Metadata

---

## 24. YouTube Title Options

### Primary (recommended)

**What REALLY Happens When Kubernetes OOMKills a Pod? (5 Layers Deep)**

### Alternatives

1. **Kubernetes OOMKilled Explained: Kubernetes Didn't Kill Your Pod — The Kernel Did**
   - Focuses on the counterintuitive reveal. High curiosity factor.

2. **Exit Code 137 Decoded: The Real Story Behind Kubernetes OOMKills**
   - Leads with the number everyone Googles after seeing it.

3. **OOMKilled Investigation: From kubectl to the Linux Kernel in 5 Layers**
   - Emphasizes the descent structure. Appeals to deep-dive viewers.

4. **Why Your Kubernetes Pod Has No Logs (OOMKilled + SIGKILL Explained)**
   - Problem-first framing. Targets people debugging RIGHT NOW.

5. **cgroups, SIGKILL, and the OOM Killer: How Kubernetes Memory Limits Actually Work**
   - Keyword-rich for search: cgroups, OOM killer, memory limits.

6. **The Empty Logs Mystery: Debugging a Kubernetes OOMKill Like an SRE**
   - Incident-story framing. Relatable to anyone who's been paged.

7. **Kubernetes Memory Limits Explained by Killing a Pod (Live Demo)**
   - Demo-forward. Sets expectation of a real, reproducible lab.

8. **OOMKilled vs Your YAML: What memory limits: 128Mi Actually Does**
   - Targets the specific YAML everyone has written.

### SEO Notes

- Primary keyword targets: `kubernetes oomkilled`, `exit code 137`, `kubernetes memory limits`, `oom killer`, `cgroups`
- Secondary keywords: `sigkill`, `container memory working set`, `crashloopbackoff`, `kubectl describe pod`, `crictl`, `dmesg oom`
- The primary title is 68 characters — within the ~70-character full-display limit.

---

## 25. Thumbnail Concept

### Thumbnail Design

**Layout:** Split-screen with contrast.

**Left side (55%):**
- Dark terminal background (#1e1e2e)
- Terminal snippet in monospace: `RESTARTS: 3` with the 3 in large red text
- Below: `LOGS: (empty)` — the emptiness highlighted with a red outline
- The words "WHO DID IT?" in bold yellow

**Right side (45%):**
- A downward staircase of 5 small layer labels (kubectl → crictl → cgroup → kernel → metrics)
- The bottom step (KERNEL) in a red box, larger than the others
- A red "SIGKILL" stamp across the corner

**Bottom banner:**
- Text: "OOMKilled, 5 Layers Deep" in white on a semi-transparent dark strip

**Overall mood:** Mystery/crime-investigation. The viewer should think "wait — Kubernetes didn't kill it? Then who?" 

### Alternative Thumbnail Concepts

**Concept B — The Cliff:**
- A simplified sawtooth graph: line climbing to a red limit line, then vertical drop
- The drop labeled "137"
- Text: "The moment your pod dies"

**Concept C — The Number:**
- Giant "137" centered, red
- Under it: "= 128 + 9 = SIGKILL"
- Text: "Kubernetes exit codes decoded"

**Concept D — The Chain:**
- Mini flow: `limits: 128Mi` → `cgroup` → `kernel` → `SIGKILL`
- Kernel node in red, rest in blue
- Text: "Kubernetes just walks away"

### Thumbnail Text Guidelines

- Keep text minimal — 3-5 words max on the thumbnail itself
- Use high contrast: white/yellow text on dark background
- Font: bold sans-serif (Inter Bold, Montserrat, or similar)
- Make the red restart counter the visual focal point
- Ensure readability at small sizes (mobile)

---

## 26. YouTube Description

### Full Description

```
What REALLY Happens When Kubernetes OOMKills a Pod? (5 Layers Deep)

Your pod restarted overnight. The logs show nothing — no exception, no stack trace, not even a goodbye. kubectl says "OOMKilled, Exit Code 137." But nobody logged in. And Kubernetes didn't kill it either. In this episode we descend through five layers — from the Kubernetes API down to the Linux kernel — to find out who actually kills your containers, and why.

We cover:
• What memory requests vs limits actually do (completely different jobs)
• What happens at container start: kubelet → containerd → cgroup
• Where your limits.memory: 128Mi REALLY lives (a file on the node)
• Why OOMKilled pods have empty logs (SIGKILL leaves no goodbye)
• How to decode exit code 137 (128 + 9 = killed by signal 9)
• Layer 1: kubectl — the after-action report
• Layer 2: crictl — the container runtime's account
• Layer 3: cgroups — memory.max, memory.current, memory.events (the smoking gun)
• Layer 4: the kernel — dmesg and the OOM killer's own confession
• Layer 5: Prometheus/Grafana — watching the kill as a sawtooth graph
• Working set vs RSS vs virtual memory — which one the kernel counts
• QoS classes — and why they DON'T protect you from a cgroup OOM kill
• The difference between cgroup OOM kills and node-level OOM kills
• A complete troubleshooting checklist for OOMKilled pods
• Prevention: right-sizing, alerting at 90% of limit, leak detection

Everything is demonstrated live on a 3-node K3s cluster on Proxmox with a full Prometheus + Grafana observability stack. The demo workload is a deliberately memory-hungry "payment service" with an /allocate endpoint — one HTTP call triggers the kill, live on camera.

⏱ Timestamps:
0:00  - Intro: the empty-logs mystery
1:30  - What is a memory limit, really? (requests vs limits vs cgroups)
4:00  - Deploying the demo workload (payment-service, 128Mi limit)
6:00  - Baseline: reading memory.max from inside the container
8:00  - TRIGGERING THE OOMKILL (live, on camera)
10:00 - Layer 1: Kubernetes API (kubectl describe, the after-action report)
12:30 - Decoding exit code 137 (128 + 9 = SIGKILL)
14:00 - Layer 2: Container runtime (crictl on the node)
16:00 - Layer 3: Cgroups (memory.events — the smoking gun)
19:00 - Layer 4: The kernel (dmesg — the executioner's log)
22:00 - Layer 5: Metrics (PromQL + Grafana sawtooth)
25:00 - Working set vs RSS vs virtual memory
27:00 - QoS classes (and the nuance nobody tells you)
28:30 - OOMKill troubleshooting checklist
30:00 - Prevention and best practices
32:00 - Cleanup and outro

🔗 Next episode:
Episode 2 — OOMKilled vs Evicted: They Are NOT the Same Thing

🛠 Lab environment:
- 3-node K3s cluster on Proxmox VMs
- Prometheus + Grafana + node-exporter + kube-state-metrics
- All manifests, scripts, and dashboard JSON in the repo

📋 Commands covered:
kubectl describe, kubectl get -o jsonpath, kubectl top, kubectl exec,
kubectl get pods -w, crictl ps -a, crictl inspect, cat memory.max,
cat memory.current, cat memory.events, dmesg -T, grep,
container_memory_working_set_bytes, kube_pod_container_status_last_terminated_reason,
container_oom_events_total

If this was helpful, subscribe for more Kubernetes internals episodes — we go under the hood every time.

#Kubernetes #OOMKilled #Linux #SRE #DevOps
```

### Short Description (for YouTube Shorts / social media)

```
Your pod restarted. The logs are EMPTY. Exit code 137. Kubernetes says it didn't kill anything — and it's telling the truth. Here's who actually did, found in the kernel's own logs. 🔍💀

Full episode: [link]
#Kubernetes #OOMKilled #DevOps #SRE
```

---

## 27. Hashtags

### Primary Hashtags (for YouTube description)

```
#Kubernetes #OOMKilled #Linux #SRE #DevOps #KubernetesTroubleshooting #Cgroups #LinuxKernel #ExitCode137 #ContainerDebugging #K8s #SiteReliabilityEngineering #MemoryManagement #Prometheus #Grafana
```

### Additional Hashtags (for social media promotion)

```
#KubernetesInternals #OOMKiller #SIGKILL #CrashLoopBackOff #K3s #Proxmox #CloudNative #PlatformEngineering #Observability #ContainerMemory #DevOpsLife #SRELife #LearnKubernetes #TechTutorial #Debugging
```

### Hashtag Strategy

| Category | Hashtags | Purpose |
|----------|----------|---------|
| Core topic | `#Kubernetes #OOMKilled #KubernetesTroubleshooting` | Primary search discovery |
| Audience | `#SRE #DevOps #PlatformEngineering` | Target audience reach |
| Specific concepts | `#Cgroups #OOMKiller #ExitCode137 #SIGKILL` | Niche search terms |
| Tools | `#Prometheus #Grafana #K3s` | Stack-specific discovery |
| Incident type | `#CrashLoopBackOff #ContainerDebugging` | Problem-led discovery |
| Broad reach | `#TechTutorial #LearnKubernetes #LinuxKernel` | General tech education |

### Platform-Specific Notes

- **YouTube:** Use 10-15 hashtags in the description. YouTube shows the first 3 above the title.
- **Twitter/X:** Use 2-3 hashtags per post for maximum engagement.
- **LinkedIn:** Use 3-5 hashtags. Focus on professional tags: `#Kubernetes #SRE #DevOps #PlatformEngineering`
- **Reddit:** No hashtags. Post in r/kubernetes, r/devops, r/sre with a descriptive title.

---

## Additional Metadata

### Category
Science & Technology → Software Tutorials

### Tags (YouTube backend, comma-separated)
```
kubernetes, oomkilled, oom killer, exit code 137, sigkill, kubernetes memory limits, cgroups, memory.max, kubernetes troubleshooting, crashloopbackoff, kubectl, crictl, dmesg, prometheus, grafana, working set, rss, kubernetes internals, container debugging, qos classes, k3s, proxmox, sre, devops, site reliability engineering, k8s, linux kernel, memory management, kubernetes tutorial
```

### Language
English

### Video Visibility
Public

### Recording Date
2026-10-XX (TBD)

### Series
Kubernetes Under the Hood — Season 1, Episode 01

### Estimated Duration
~33 minutes

### Content Rating
No sensitive content (educational technical content)

### Monetization
Eligible (educational, advertiser-friendly content)

### Captions/Subtitles
Provide .srt file with full narration. English captions required. Consider auto-translating to Spanish, Portuguese, French, German, Hindi.

---

*End of Metadata*
