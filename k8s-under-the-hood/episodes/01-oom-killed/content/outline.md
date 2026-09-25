# Episode 1 — Long-Form Outline

**Title:** What REALLY happens when Kubernetes OOMKills a pod?
**Audience:** Kubernetes users who have seen OOMKilled but never gone below the API
**Companion demo:** `make demo-ep01`

---

## 1. The mystery (2 min)

- Pod restarts. Logs show nothing. No exception, no stack trace — the process never got a chance to speak
- `kubectl describe pod`: `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`
- Decode 137: 128 = "killed by a signal", 9 = SIGKILL. A signal that cannot be caught, blocked, or ignored
- Thesis: **Kubernetes never killed your container. It only wrote down what the kernel did.**

## 2. The setup — where the limit actually lives (3 min)

- A Deployment's `limits.memory: 128Mi` does not summon a Kubernetes memory police
- What really happens at scheduling + container start:
  1. Scheduler uses `requests` to pick a node
  2. kubelet tells containerd to start the container
  3. containerd creates a **cgroup** on the node and writes `memory.max = 134217728`
  4. Everyone walks away. From now on it's between the container and the kernel
- Show the file: `cat /sys/fs/cgroup/k8s.io/.../memory.max`

## 3. The demo — healthy, then dead (5 min)

- Deploy payment-service (64Mi requests / 128Mi limits, Burstable QoS)
- Baseline: `kubectl top pod`, `/usage`, working set ~20 MB
- Trigger: `POST /allocate?mb=200`
- Watch on Grafana: working set → limit → kill → fresh restart → low memory (the sawtooth)
- `kubectl get pods -w` catches the restart in the act

## 4. The 5-layer investigation (10 min)

- **Layer 1 — Kubernetes API**: `kubectl describe pod` — the after-action report. `lastState.terminated.reason: OOMKilled`. JSON path walk through `.status.containerStatuses[0]`
- **Layer 2 — Container runtime**: `crictl ps -a` shows the dead container; `crictl inspect` gives exitCode 137 + reason. Note: runtime may GC the container fast — the API keeps the story longer
- **Layer 3 — cgroups**: `memory.max` (the limit), `memory.current` (usage), **`memory.events` → `oom_kill` counter** — the courtroom where the limit is enforced. This file incrementing IS the kill
- **Layer 4 — Kernel**: `dmesg` — "Out of memory: Killed process 12345 (python)". The kernel memory allocator invoked the OOM killer; it selected the only process in the cgroup; SIGKILL. Also explain: cgroup OOM vs node OOM (the killer has two modes)
- **Layer 5 — Metrics**: PromQL trio — working set vs limit, `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`, `container_oom_events_total`. Metrics are history; layers 1–4 are the present

## 5. Concepts that click after this demo (5 min)

- **QoS classes**: requests < limits = Burstable. Why Guaranteed pods get killed differently at node level (but a cgroup kill doesn't care about QoS)
- **working_set vs RSS vs virtual memory**: the kernel counts `working_set` (RSS minus inactive file cache) against the limit — not `VmSize` (why "I have 2GB virtual" doesn't matter)
- **OOMKilled ≠ Evicted** — teaser for Episode 2 (node pressure, the scheduler's involvement, `Pod Evicted` vs container restart)
- **Prevention preview** (Episode 4): set sane limits, watch trends, alert at 90% of limit, don't set limits lower than the app's normal working set

## 6. Recap graphic (1 min)

```
limits.memory: 128Mi
      │ kubelet → containerd
      ▼
cgroup memory.max = 134217728          (Layer 3)
      │ container allocates 200MB
      ▼
kernel can't satisfy memory.max        (Layer 4)
      │
      ▼
OOM killer → SIGKILL → exit 137        (exit code 137 = 128 + 9)
      │ containerd reports it
      ▼
kubectl: OOMKilled                     (Layer 1 — the summary)
      │ scraped later
      ▼
Prometheus graphs                      (Layer 5 — the history)
```
