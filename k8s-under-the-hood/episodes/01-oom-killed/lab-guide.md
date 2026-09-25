# What REALLY Happens When Kubernetes OOMKills a Pod?
## Lab Guide & Runbook

> **Series:** Kubernetes Under the Hood — Season 1 (Resource & Failure Internals)
> **Episode:** 01 — What REALLY happens when Kubernetes OOMKills a Pod?
> **Lab Environment:** 3-node K3s cluster on Proxmox VMs (local, no cloud costs)
> **Safety:** All work runs in the `shopnow` namespace. The cluster, monitoring stack, and other workloads are untouched. Cleanup is one command.

---

## Table of Contents

1. [Episode Overview](#1-episode-overview)
2. [Learning Objectives](#2-learning-objectives)
3. [Final Lab Architecture](#3-final-lab-architecture)
4. [Prerequisites](#4-prerequisites)
5. [Deploy the Demo Workload](#5-deploy-the-demo-workload)
6. [Baseline: Everything Looks Healthy](#6-baseline-everything-looks-healthy)
7. [Trigger the OOMKill](#7-trigger-the-oomkill)
8. [Layer 1 — Kubernetes API Investigation](#8-layer-1--kubernetes-api-investigation)
9. [Decode Exit Code 137](#9-decode-exit-code-137)
10. [Layer 2 — Container Runtime Investigation](#10-layer-2--container-runtime-investigation)
11. [Layer 3 — Cgroups Investigation](#11-layer-3--cgroups-investigation)
12. [Layer 4 — Kernel Investigation](#12-layer-4--kernel-investigation)
13. [Layer 5 — Metrics Investigation](#13-layer-5--metrics-investigation)
14. [Concepts: Working Set vs RSS vs Virtual Memory](#14-concepts-working-set-vs-rss-vs-virtual-memory)
15. [Concepts: QoS Classes](#15-concepts-qos-classes)
16. [Troubleshooting Checklist](#16-troubleshooting-checklist)
17. [Prevention / Best Practices](#17-prevention--best-practices)
18. [Cleanup / Reset](#18-cleanup--reset)
19. [Hashtags](#19-hashtags)

---

## 1. Episode Overview

This episode is built around a realistic production incident:

> Your pod restarted overnight. Logs show nothing — no exception, no stack trace, no goodbye. `kubectl describe pod` says `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`. But nobody logged in and killed it. Kubernetes says it didn't kill it either.

We investigate from **symptom** to **root cause** across **five layers** — Kubernetes API → container runtime → cgroups → kernel → metrics — following the same descent path a senior engineer would take during a real incident.

**The primary incident:** A memory-hungry application exceeds its container memory limit and is killed by the kernel's OOM killer.

**The key revelation:** Kubernetes NEVER kills your container. It writes a limit into a cgroup file and walks away. The KERNEL pulls the trigger.

We do NOT reveal the root cause upfront. We discover it through investigation, layer by layer.

---

## 2. Learning Objectives

By the end of this episode, you will understand:

1. What a Kubernetes memory limit actually does (and doesn't do).
2. What happens at container start: kubelet → containerd → cgroup.
3. What `OOMKilled` and `Exit Code 137` mean, and how to decode them.
4. How to investigate an OOMKilled pod at 5 layers: kubectl, crictl, cgroups, dmesg, PromQL.
5. Why the kernel — not Kubernetes — terminates the container.
6. What the cgroup `memory.max`, `memory.current`, and `memory.events` files tell you.
7. How to read the kernel's OOM killer output in `dmesg`.
8. What `working set` means and why the kernel counts it (not virtual memory) against the limit.
9. How QoS classes (Guaranteed/Burstable/BestEffort) relate to memory.
10. How to detect and graph OOMKills in Prometheus/Grafana.
11. The difference between OOMKilled and Evicted (teaser for Episode 2).
12. How to prevent OOMKills in production.

---

## 3. Final Lab Architecture

```
                    Proxmox
                   /    |    \
                 pve2  pve3  pve4
                  |     |     |
              K3s VM  K3s VM  K3s VM     <- 3-node cluster
                  \    |    /
                   \   |   /
                [ K3s control plane ]
                        |
         +--------------+----------------+
         |                               |
   monitoring ns                    shopnow ns
   (Prometheus, Grafana,          payment-service
    node-exporter,                 64Mi req / 128Mi limit
    kube-state-metrics)                 |
                                   /allocate?mb=200
                                         |
                                         v
                              working set > 128Mi
                                         |
                                         v
                              KERNEL OOM KILLER
                                         |
                                         v
                            SIGKILL -> exit 137
                                         |
                                         v
                          pod restarts (restartCount +1)
```

**Components:**

| Component | Purpose |
|-----------|---------|
| 3-node K3s cluster (Proxmox VMs) | Safe, isolated lab cluster |
| `monitoring` namespace | Prometheus + Grafana + node-exporter + kube-state-metrics (pre-existing) |
| `shopnow` namespace | Episode demo workload — created and destroyed by this lab |
| `payment-service` Deployment | 1 replica, 64Mi requests / 128Mi limits, Burstable QoS |
| `mem-hog.py` (ConfigMap) | Demo app: `POST /allocate?mb=N` allocates and holds memory |
| Grafana dashboard `oom-investigation.json` | 5-panel visual of the kill |

---

## 4. Prerequisites

### 4.1 Environment

- The K8s Under the Hood lab running: `make verify` passes (3 nodes Ready, observability pods up).
- Kubeconfig at `~/.kube/config-k8suth` (or `KUBECONFIG` set).
- For Layers 2–4: SSH access to a K3s node (the demo prints which node the pod runs on).

### 4.2 Set the kubeconfig

```bash
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
```

```
NAME       STATUS   ROLES                  AGE   VERSION
k8s-uth-1  Ready    control-plane,master   2d    v1.30.x+k3s1
k8s-uth-2  Ready    <none>                 2d    v1.30.x+k3s1
k8s-uth-3  Ready    <none>                 2d    v1.30.x+k3s1
```

**Why we run it:** Confirms the cluster is reachable before starting.

### 4.3 One-command alternative

The entire episode demo is also automated:

```bash
make demo-ep01      # guided walkthrough with pause points
make cleanup-ep01   # teardown (keeps the lab)
```

The lab guide below runs the same steps manually so you understand each command.

---

## 5. Deploy the Demo Workload

### 5.1 What we're deploying

```yaml
# excerpt: episodes/01-oom-killed/manifests/payment-service.yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi      # scheduler uses this
  limits:
    cpu: 250m
    memory: 128Mi     # <- becomes cgroup memory.max
```

**Why it matters:** `limits.memory: 128Mi` is the number the whole episode revolves around. At container start, kubelet tells containerd to create a cgroup with `memory.max = 134217728`. From then on, Kubernetes is NOT watching this container's memory — the kernel is.

### 5.2 Deploy

```bash
kubectl apply -f episodes/01-oom-killed/manifests/payment-service.yaml
```

```
namespace/shopnow created
configmap/payment-service-code created
deployment.apps/payment-service created
service/payment-service created
```

### 5.3 Wait for ready

```bash
# NOTE: `kubectl wait --for=condition=ready pod -l ...` can race the
# Deployment controller ("no matching resources found") — rollout status
# cannot race.
kubectl rollout status deployment/payment-service -n shopnow --timeout=180s
```

```
deployment "payment-service" successfully rolled out
```

### 5.4 Record the pod and node

```bash
POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl get pod -n shopnow $POD -o jsonpath='{.spec.nodeName}')
echo "Pod: $POD | Node: $NODE"
```

**Why we run it:** Layers 2–4 require SSH'ing to `$NODE`. Note it down.

---

## 6. Baseline: Everything Looks Healthy

### 6.1 Pod status

```bash
kubectl get pod -n shopnow $POD
```

```
NAME                       READY   STATUS    RESTARTS   AGE
payment-service-7d9c6b5f4-x2k8p   1/1     Running   0          30s
```

### 6.2 App-reported memory

```bash
# NOTE: the pod image (python:3.12-slim) has no curl/wget — use python.
kubectl exec -n shopnow $POD -- python -c 'import urllib.request as u; print(u.urlopen("http://localhost:8080/usage").read().decode(), end="")'
```

```
rss_mb=18.4
```

**Why we run it:** ~18 MB of ~128 MB limit. Comfortably healthy.

### 6.3 The limit as the kernel sees it

```bash
kubectl exec -n shopnow $POD -- cat /sys/fs/cgroup/memory.max
```

```
134217728
```

**Why we run it:** This IS the memory limit — a cgroup file inside the node, visible from inside the container. `134217728 = 128 × 1024 × 1024`. Kubernetes wrote this file at container start. Hold this number in your head.

### 6.4 (Optional) Grafana dashboard

```bash
# Grafana is exposed directly on every node (LoadBalancer, pinned port):
#   http://192.168.1.81:30300  (admin/admin)
# (or any node IP: .82 / .83)
# Dashboards -> Import -> episodes/01-oom-killed/dashboards/oom-investigation.json
```

Leave the "Working Set vs Limit" panel open — you'll watch the kill happen live.

---

## 7. Trigger the OOMKill

### 7.1 Allocate past the limit

```bash
# NOTE: python, not curl — the image has no curl.
kubectl exec -n shopnow $POD -- python -c 'import urllib.request as u; print(u.urlopen(u.Request("http://localhost:8080/allocate?mb=200", method="POST")).read().decode(), end="")'
```

```
allocated 200 MB; rss_mb=219.7
```

**Why we run it:** The app now holds 200 MB it will never release — simulating a caching bug or leak. The working set is now past the 128 MiB cgroup limit. The kernel notices within seconds.

> Note: this curl may itself get killed mid-response — the OOM killer doesn't wait politely.

### 7.2 Watch the death

```bash
kubectl get pods -n shopnow -w
```

Within seconds you'll see `RESTARTS` tick from `0` to `1` (Status may briefly show the pod still `Running` — the CONTAINER restarted, the POD object stayed).

```
NAME                       READY   STATUS    RESTARTS   AGE
payment-service-7d9c6b5f4-x2k8p   1/1     Running   1          2m
```

(Ctrl+C to stop the watch.)

**What just happened:** the kernel's OOM killer sent SIGKILL to the container's process. Kubernetes noticed, recorded `OOMKilled`, and restarted the container per the Deployment's `restartPolicy: Always`.

---

## 8. Layer 1 — Kubernetes API Investigation

### 8.1 The summary view

```bash
kubectl describe pod -n shopnow $POD
```

Key section:

```
Containers:
  payment-service:
    ...
    State:          Running
      Started:      <just now — this is the NEW container>
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      <original start>
      Finished:     <moment of death>
    Restart Count:  1
```

### 8.2 The structured view

```bash
kubectl get pod -n shopnow $POD -o jsonpath='{.status.containerStatuses[0].lastState}' | python3 -m json.tool
```

```json
{
    "terminated": {
        "exitCode": 137,
        "reason": "OOMKilled",
        "startedAt": "...",
        "finishedAt": "...",
        "containerID": "containerd://abc123..."
    }
}
```

### 8.3 Interpretation — what Layer 1 tells you

| Field | Meaning |
|---|---|
| `reason: OOMKilled` | The container was killed because it exceeded its memory limit |
| `exitCode: 137` | 128 + 9 = "killed by signal" + SIGKILL |
| `containerID` | The dead container, as containerd knew it |

**Critical insight:** `kubectl` is an AFTER-ACTION REPORT. Kubernetes didn't kill anything — it watched the container die and wrote it down. To find the actual killer, we go to the node.

---

## 9. Decode Exit Code 137

```bash
python3 -c "print(137, '=', 128, '+', 137 - 128, '(SIGKILL)')"
```

**The rule:** exit codes ≥ 128 mean the process died from a SIGNAL. The signal number is `exitCode − 128`.

```
137 − 128 = 9 = SIGKILL
```

**SIGKILL** cannot be caught, blocked, or ignored. The process never ran another line of code — which is why the application logs show NOTHING. No exception handler, no shutdown hook, no final log line. The process ceased to exist between two CPU instructions.

That's why the logs are empty and that's your first clue the killer was below the application layer.

---

## 10. Layer 2 — Container Runtime Investigation

SSH to the node the pod runs on (from Step 5.4):

```bash
ssh <user>@$NODE
```

### 10.1 All containers, including dead ones

```bash
sudo crictl ps -a | grep payment-service
```

```
CONTAINER      IMAGE              ...  STATE     NAME
9f3c...        python:3.12-slim   ...  Exited    payment-service
a1b2...        python:3.12-slim   ...  Running   payment-service
```

(Two entries: the dead container and its replacement.)

### 10.2 Inspect the dead container

```bash
CID=$(sudo crictl ps -a -q --name payment-service | tail -1)
sudo crictl inspect $CID | grep -A5 '"exitCode"'
```

```json
"exitCode": 137,
"reason": "OOMKilled",
"finishedAt": "..."
```

### 10.3 Interpretation — what Layer 2 tells you

containerd — the thing that actually created the container's namespaces and cgroup — confirms: the process exited 137, killed by signal. Same fact as Layer 1, but closer to the metal: this is the runtime that spawned the process, reporting how it died.

> **Note:** the runtime may garbage-collect the dead container quickly. Kubernetes keeps the story longer — that's why we started at Layer 1.

---

## 11. Layer 3 — Cgroups Investigation

Still on the node. This is where the limit LIVES.

### 11.1 Find the pod's cgroup

On K3s, cgroup paths use the **pod UID** (not the namespace), and
`crictl inspect`'s `runtimeSpec.cgroupsPath` is often null — derive the path
from the pod UID instead:

```bash
# on your workstation — get the pod UID
POD_UID=$(kubectl get pod -n shopnow $POD -o jsonpath='{.metadata.uid}')

# on the node — the pod's cgroup slice (burstable QoS for this demo;
# guaranteed pods live in kubepods-pod..., besteffort in kubepods-besteffort-pod...)
CG=/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod${POD_UID//-/_}.slice
echo $CG
```
> The pod-level slice survives container restarts — the per-container
> `cri-containerd-<cid>.scope` is garbage-collected quickly, but the pod
> slice keeps the counters. That's where the evidence stays.

### 11.2 The three files that matter

```bash
echo "memory.max:";     cat $CG/memory.max
echo "memory.current:"; cat $CG/memory.current
echo "memory.events:";  cat $CG/memory.events
```

```
memory.max:      134217728        <- the limit (your 128Mi from the YAML)
memory.current:  23592960         <- usage right now (fresh container, low)
memory.events:
  low 0
  high 0
  max 20           <- allocations were blocked at the limit
  oom 1            <- the kernel attempted an OOM kill in this cgroup
  oom_kill 4       <- the kernel COMPLETED kills here. Smoking gun.
  oom_group_kill 1
```

### 11.3 Interpretation — what Layer 3 tells you

| File | Meaning |
|---|---|
| `memory.max` | The hard ceiling written by containerd at container start |
| `memory.current` | Live usage (this is a fresh container, so it's low) |
| `memory.events` → `oom_kill: 1` | **The kernel's own counter: an OOM kill happened HERE, in this cgroup** |

This file is the courtroom. `oom_kill` incrementing means: the kernel could not satisfy `memory.current ≤ memory.max`, invoked the OOM killer, and terminated a process inside this cgroup. Kubernetes never touched this file.

---

## 12. Layer 4 — Kernel Investigation

Still on the node. The killer's own log.

### 12.1 The OOM killer output

```bash
sudo dmesg -T | grep -i -A5 "out of memory"
```

```
[...] Out of memory: Killed process 18734 (python) total-vm:1234567kB, ...
[...] oom_reaper: reaped process 18734 (python), now anon-rss:0kB, ...
```

### 12.2 Interpretation — what Layer 4 tells you

This is the truth, from the component that pulled the trigger:

1. A process in the pod's cgroup tried to allocate memory.
2. The kernel could not satisfy the allocation within the cgroup's `memory.max`.
3. The cgroup OOM killer selected the largest process in the cgroup (our python app — the only one).
4. It sent SIGKILL. The `oom_reaper` then freed the memory.

**The chain is complete:** `limits.memory: 128Mi` (YAML) → `memory.max` (cgroup) → allocation failure (kernel) → SIGKILL (exit 137) → `OOMKilled` (Kubernetes summary).

### 12.3 Two OOM killers (brief side-path)

- **cgroup OOM kill** (what we just saw): the limit of ONE container was exceeded. Only processes inside that cgroup are candidates. This is what "OOMKilled" means.
- **node OOM kill**: the WHOLE machine is out of memory. The global killer scores ALL processes (and may sacrifice pods with lower QoS first). This produces Evictions and node-level events — Episode 2 territory.

---

## 13. Layer 5 — Metrics Investigation

Back on your workstation.

### 13.1 Prometheus

```bash
# Prometheus is exposed directly on every node (LoadBalancer, pinned port):
#   http://192.168.1.81:30900
# (or any node IP: .82 / .83)
```

Run these queries (full list in `episodes/01-oom-killed/promql/queries.md`):

```promql
# The cliff: working set vs limit
container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}
```
Graph both: the usage line rockets to the limit and drops (the kill), then restarts low — the sawtooth.

```promql
# The Kubernetes-visible verdict
kube_pod_container_status_last_terminated_reason{namespace="shopnow", reason="OOMKilled"}
```
Flips to 1 at the kill.

```promql
# The kernel-visible kill counter (cAdvisor scrapes memory.events)
increase(container_oom_events_total{namespace="shopnow"}[10m])
```

> Nuance (observed live): this counter is per-container and resets when the
> container restarts. If the kill falls between Prometheus's 15s scrapes,
> `increase()` can read 0 — the kill was too fast to be sampled. The
> authoritative counter is the pod-level cgroup's `memory.events`
> (`oom_kill`, Layer 3), which persists across restarts. Trust the cgroup.

### 13.2 Grafana

Import `episodes/01-oom-killed/dashboards/oom-investigation.json` (Dashboards → Import). Five panels: the cliff, % of limit, OOMKilled flag, restarts, kernel kill counter.

### 13.3 Interpretation — what Layer 5 tells you

Metrics are the HISTORICAL RECORD. Layers 1–4 showed you the present; Layer 5 lets you see the trend that led here — working set creeping toward the limit for minutes before the kill. This is how you catch the NEXT one before it happens.

---

## 14. Concepts: Working Set vs RSS vs Virtual Memory

Three different "memory" numbers, and the kernel only counts one of them:

```
Virtual memory (VmSize)     "I have MAPPED 2 GB"        <- irrelevant to the limit
     |
RSS                         "I am TOUCHING 500 MB"      <- close, but includes file cache
     |
Working set                 "I am USING 220 MB"         <- THIS is what counts
     (RSS minus inactive file cache)
```

The kernel charges the **working set** (`container_memory_working_set_bytes` in Prometheus) against `memory.max`. That's why "but the app only maps 2GB of virtual space" doesn't save you — and why inactive page cache can be reclaimed instead of killing you. When the WORKING SET crosses the limit, the OOM killer wakes up.

---

## 15. Concepts: QoS Classes

```yaml
requests == limits          -> Guaranteed     (last to be node-OOM-killed)
requests <  limits          -> Burstable       (our pod: 64Mi < 128Mi)
no requests/limits           -> BestEffort     (first to be node-OOM-killed)
```

**Important nuance:** QoS matters for NODE-level memory pressure (who gets evicted first — Episode 2). It does NOT protect you from a **cgroup** OOM kill. If you set your own limit to 128Mi and blow past it, your QoS class is irrelevant — the cgroup limit is enforced regardless.

**Rule of thumb:** set limits ≥ your app's real peak working set + headroom, or omit memory limits entirely in favor of careful requests (a debate we'll have in Episode 4).

---

## 16. Troubleshooting Checklist

```
OOMKILLED POD — INVESTIGATION CHECKLIST

1. kubectl describe pod $POD
   -> Last State: OOMKilled? Exit Code 137? Restart Count climbing?

2. kubectl top pod -n $NS (or /usage) — is it CLOSE to the limit even when "healthy"?

3. Was it a ONE-TIME spike or a LEAK?
   -> graph container_memory_working_set_bytes over 1h/24h/7d
   -> steadily climbing = leak; sawtooth = limit too low; flat+spike = data-driven load

4. Is it the container's cgroup or the whole NODE?
   -> kubectl describe node | grep -A10 "Memory Pressure"
   -> node-level = Eviction territory (Episode 2)

5. What does the app ACTUALLY need at peak?
   -> compare peak working set vs current limit

6. Fix options (see Section 17) — and set an ALERT at 90% of limit so
   the next one pages you BEFORE the kill.
```

---

## 17. Prevention / Best Practices

1. **Right-size limits** — base them on measured peak working set (P95/P99), not guesses. `kubectl top` + Prometheus history is your friend.
2. **Alert at 90% of limit** — `100 * working_set / limit > 90` for 5m. An OOMKill you predicted is an event; one you didn't is an outage.
3. **Watch the trend, not the point** — a slow leak crosses any limit eventually. `rate()`/`deriv()` on working set catches leaks.
4. **Don't set limits you can't afford** — a limit lower than the app's normal working set guarantees a CrashLoop.
5. **Distinguish leak vs load** — leak: memory climbs monotonically even at idle. Load: memory tracks traffic.
6. **Fix leaks at the source** — the demo app's `/release` endpoint exists; production leaks need profiling, not bigger limits.
7. **Consider omitting memory limits** for well-behaved critical services, relying on requests + node capacity — with the tradeoffs discussed in Episode 4.

---

## 18. Cleanup / Reset

```bash
make cleanup-ep01
```

or manually:

```bash
kubectl delete namespace shopnow
```

```
namespace "shopnow" deleted
```

The cluster, `monitoring` namespace, and observability stack are untouched — ready for Episode 2 (OOMKilled vs Evicted).

---

## 19. Hashtags

```
#Kubernetes #OOMKilled #Linux #SRE #DevOps #KubernetesTroubleshooting #Cgroups #LinuxKernel #ExitCode137 #ContainerDebugging #K8s #SiteReliabilityEngineering #MemoryManagement #Prometheus #Grafana
```

---

*End of Lab Guide*
