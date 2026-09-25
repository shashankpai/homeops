# Episode 1 — Short-Form Script

**Title:** What REALLY happens when Kubernetes OOMKills a pod?
**Runtime target:** 60–90 seconds
**Format:** screen-recorded demo with voiceover

---

## The Script

**[0:00 — HOOK — screen: `kubectl get pods` showing restarts climbing]**

> "Your pod restarted. Again. `CrashLoopBackOff`. You check the logs — nothing. No exception, no error, no goodbye. It just... died. Here's what actually happened — five layers deep."

**[0:08 — LAYER 1 — screen: `kubectl describe pod`, zoom on Last State]**

> "Kubernetes tells you the summary: Last State Terminated, Reason OOMKilled, Exit Code 137. But Kubernetes didn't kill anything. 137 means the process died from signal 9 — SIGKILL. Kubernetes just wrote that down."

**[0:20 — THE LIMIT — screen: Deployment YAML, zoom `limits.memory: 128Mi`]**

> "Here's the setup. The pod has a memory limit: 128 megs. When Kubernetes starts this container, it doesn't police that number — it writes it into a cgroup file on the node and walks away."

**[0:30 — TRIGGER — screen: `curl -X POST /allocate?mb=200`, then the dashboard]**

> "Now watch. I tell the app to allocate 200 megs. On the graph: the working set climbs toward the limit... touches it — and the container drops dead."

**[0:45 — LAYERS 2+3 — screen: SSH to node, `crictl inspect`, `cat memory.events`]**

> "On the node, the container runtime confirms exit code 137. And here — the cgroup's `memory.events` file: `oom_kill: 1`. The kernel's own counter."

**[0:58 — LAYER 4 — screen: `dmesg | grep -i 'out of memory'`]**

> "And here's the kernel's own log: 'Out of memory: Killed process...' The kernel couldn't satisfy the limit, so its OOM killer picked our process and sent SIGKILL. Cannot be caught. Cannot be blocked."

**[1:10 — PAYOFF — screen: 5-layer recap graphic]**

> "So the chain is: limit goes into a cgroup file — kernel enforces it — OOM killer fires — SIGKILL — exit 137 — Kubernetes writes 'OOMKilled' afterward. Kubernetes didn't kill your pod. The kernel did. Next: OOMKilled vs Evicted — they are NOT the same."

---

## Shot list

| # | Shot | Screen action | Duration |
|---|------|--------------|----------|
| 1 | Hook | `kubectl get pods -w` — restarts increment | 8s |
| 2 | Layer 1 | `kubectl describe pod` — zoom Last State block | 12s |
| 3 | Setup | YAML editor — zoom `limits.memory: 128Mi` | 10s |
| 4 | Trigger | Terminal: `/allocate?mb=200` → cut to Grafana sawtooth | 15s |
| 5 | Layer 2 | Node SSH: `crictl ps -a` + `crictl inspect` | 10s |
| 6 | Layer 3 | `cat memory.max` / `memory.events` (oom_kill: 1) | 8s |
| 7 | Layer 4 | `dmesg -T \| grep -i oom` | 12s |
| 8 | Recap | 5-layer graphic | 15s |
