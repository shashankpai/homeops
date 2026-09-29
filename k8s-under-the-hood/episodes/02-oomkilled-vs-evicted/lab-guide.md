# OOMKilled vs Evicted — They Are NOT the Same
## Lab Guide & Runbook

> **Episode 2 of the Kubernetes Under the Hood series.**
> Two pods died last night. One restarted 3 times. The other just vanished.
> Same cluster — two different killers.

**Quick demo:** `make demo-ep02` (guided, interactive) · **Cleanup:** `make cleanup-ep02`

---

## Table of Contents

1. [Episode Overview](#1-episode-overview)
2. [Learning Objectives](#2-learning-objectives)
3. [Lab Architecture](#3-lab-architecture)
4. [Prerequisites](#4-prerequisites)
5. [Configure the Eviction Threshold (one-time, reversible)](#5-configure-the-eviction-threshold-one-time-reversible)
6. [Deploy the Memory Hogs](#6-deploy-the-memory-hogs)
7. [Baseline: The Node Is Healthy](#7-baseline-the-node-is-healthy)
8. [Trigger: Fill the Node](#8-trigger-fill-the-node)
9. [The Eviction](#9-the-eviction)
10. [Investigation: Evicted vs OOMKilled](#10-investigation-evicted-vs-oomkilled)
11. [On the Node: The Kubelet's Side](#11-on-the-node-the-kubelets-side)
12. [Metrics: Watching It Happen](#12-metrics-watching-it-happen)
13. [The Comparison Table](#13-the-comparison-table)
14. [Cleanup / Reset](#14-cleanup--reset)

---

## 1. Episode Overview

Episode 1 found the kernel killing a container that crossed its own cgroup
limit. This episode is the other memory death — **eviction** — where the
**kubelet** deletes whole pods because the **node** ran low. The demo fills
a worker node's memory with BestEffort pods until the eviction threshold
trips, then contrasts the two deaths side by side.

| | OOMKilled (Ep 1 recap) | Evicted (this episode) |
|---|---|---|
| **Killer** | Linux kernel (cgroup OOM killer) | kubelet eviction manager |
| **Trigger** | container exceeded its OWN limit | node-level shortage (`memory.available`) |
| **Scope** | one container process | whole pods, chosen by QoS ranking |
| **QoS relevance** | none — any class can be OOMKilled | everything — BestEffort dies first |
| **Pod after death** | Running, RESTARTS +1, stays on node | Failed, deleted from node, rescheduled |
| **Evidence** | `memory.events`, `dmesg` | events, node conditions, kubelet logs |

## 2. Learning Objectives

By the end of this episode you can:

- Explain the difference between a cgroup OOM kill and a kubelet eviction
- Name the four eviction signals and the default hard thresholds
- Read `kubectl describe pod` output and tell an eviction from an OOMKill
- Explain the eviction ranking (BestEffort → Burstable → Guaranteed) and
  why usage-over-requests is the ranking metric
- Recognize `MemoryPressure` node conditions and what they mean for scheduling
- Configure kubelet eviction thresholds on a K3s worker
- Query the whole story in Prometheus (`node_memory_MemAvailable_bytes`,
  `kube_pod_status_reason`, `kube_node_status_condition`)

## 3. Lab Architecture

```
                        ┌──────────────────────────────┐
                        │  k8suth-master (control plane)│
                        │  - K3s server                │
                        │  - Prometheus :30900         │
                        │  - Grafana :30300             │
                        └──────────────────────────────┘

┌──────────────────────────┐        ┌──────────────────────────┐
│  TARGET WORKER (one of   │        │  OTHER WORKER             │
│  the agents — demo.sh    │        │  - untouched control      │
│  picks it dynamically)   │        │  - evicted hogs may       │
│                          │        │    reschedule here       │
│  - 3× memory-hog         │        └──────────────────────────┘
│    (BestEffort, no       │
│     requests/limits)     │
│  - memory.available      │
│    drained below the     │
│    eviction threshold    │
│  - kubelet evicts hogs   │
└──────────────────────────┘

  Contrast victim: shopnow/payment-service (Ep 1, Burstable 64Mi/128Mi)
  — runs through the pressure and survives, proving QoS protection.
```

Key moving parts:

- **memory-hog** (`eviction-demo` namespace): 3 BestEffort replicas pinned to
  the target worker via `nodeSelector` (substituted at deploy time by demo.sh)
- **payment-service** (`shopnow` namespace): Episode 1's Burstable workload —
  deployed automatically by demo.sh if missing
- **Eviction threshold**: configured on the target worker (Section 5)

## 4. Prerequisites

- The lab is up (`make verify` passes), observability stack running
- `kubectl` configured (`export KUBECONFIG=~/.kube/config-k8suth`)
- The eviction dashboard imported in Grafana:
  `episodes/02-oomkilled-vs-evicted/dashboards/eviction-investigation.json`
  (Grafana at http://192.168.1.81:30300, any node IP — admin/admin)

## 5. Configure the Eviction Threshold (one-time, reversible)

The kubelet's default hard threshold is `memory.available<100Mi` — meaning the
node must be almost completely full before eviction fires. On a 4GB worker
that means allocating ~3GB, which is slow and uncomfortably close to
destabilizing the node.

For the demo we raise the threshold to **1Gi** on the target worker: we only
need to fill ~2GB, and as a bonus we learn where eviction thresholds live.

> This step is **reversible** — Section 14 shows how to restore the default.

From your controller, SSH to the target worker (the demo script prints the
node name; workers are 192.168.1.82 and 192.168.1.83):

```bash
# pick the worker demo.sh will target — or run this on whichever you prefer
# (the node name is shown by: kubectl get nodes -l node-role.kubernetes.io/agent)
WORKER_IP=192.168.1.83   # example: worker2

ssh -i lab/ssh/id_rsa ubuntu@$WORKER_IP

# On the worker: add the kubelet eviction arg to the K3s agent config.
# (The lab's Ansible install uses env vars only — this file doesn't exist yet,
#  so we create it fresh. K3s merges it with the env config.)
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml << 'EOF'
kubelet-arg:
  - "eviction-hard=memory.available<1Gi"
EOF

# Restart the agent to pick up the config
sudo systemctl restart k3s-agent

# Verify the kubelet picked it up (look for --eviction-hard in the args)
ps aux | grep kubelet | grep -o 'eviction-hard=[^ ]*'
exit
```

> **Why this matters on camera:** this file IS the eviction threshold. There
> is no API for it — it's kubelet configuration. Point at it in the episode.

<details>
<summary>Alternative: keep the default 100Mi threshold</summary>

The demo works with the default — demo.sh just needs more rounds to fill the
node (~3GB on a 4GB worker). Risk: less headroom for node stability. Only do
this if you can't modify the worker.
</details>

## 6. Deploy the Memory Hogs

The manifest has a `__WORKER_NODE__` placeholder; the script substitutes the
node name (discover yours with `kubectl get nodes -l node-role.kubernetes.io/agent`):

```bash
NODE=$(kubectl get nodes -l node-role.kubernetes.io/agent -o jsonpath='{.items[0].metadata.name}')
sed "s/__WORKER_NODE__/$NODE/" episodes/02-oomkilled-vs-evicted/manifests/memory-hog.yaml | kubectl apply -f -

kubectl rollout status deployment/memory-hog -n eviction-demo --timeout=180s
kubectl get pods -n eviction-demo -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,QOS:.status.qosClass
```

Note in the output: **QOS: BestEffort**. No requests, no limits. The kernel
will never OOMKill these pods per-container — there is no limit to cross.
Only the node running out can kill them, via the kubelet.

## 7. Baseline: The Node Is Healthy

```bash
NODE=<the node you pinned>   # from the previous step
kubectl top node $NODE
kubectl describe node $NODE | grep -A 6 "Conditions:"
```

`MemoryPressure` is `False`. In Grafana (dashboard "Episode 2 — Eviction
Investigation"), note where `node_memory_MemAvailable_bytes` sits relative to
the red 1Gi threshold line. That gap is what we're about to consume.

## 8. Trigger: Fill the Node

demo.sh ramps +256MB per hog per round and checks the node between rounds:

```bash
make demo-ep02        # guided — pause at each step
```

Or manually — allocate on every hog:

```bash
for pod in $(kubectl get pods -n eviction-demo -l app=memory-hog -o jsonpath='{.items[*].metadata.name}'); do
  kubectl exec -n eviction-demo $pod -- python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=256', method='POST')).read().decode(), end='')"
done
```

Each round takes ~4 minutes (2MB every 2s per hog — deliberately paced so
Prometheus's 15s scrape interval catches the drain in Grafana). Watch the
`node_memory_MemAvailable_bytes` panel fall toward the red threshold line.

## 9. The Eviction

When `memory.available` crosses the threshold, the kubelet acts within its
housekeeping interval (~10s). Watch for it:

```bash
kubectl get pods -n eviction-demo -w
```

What you'll see:

```
NAME                          READY   STATUS    RESTARTS   AGE
memory-hog-5d9c6b5f4-2k8p    1/1     Running   0          5m
memory-hog-5d9c6b5f4-7tq1    0/1     Evicted   0          5m
memory-hog-5d9c6b5f4-9xz3    0/1     Evicted   0          5m
```

**STATUS: Evicted.** No restart count, no OOMKilled, no exit code story —
the pod is dead and the Deployment must recreate it elsewhere. Then the
smoking gun:

```bash
kubectl get events -n eviction-demo --sort-by=.lastTimestamp | grep -i evict
```

```
The node was low on resource: memory. Threshold quantity: 1Gi, available: 999Mi.
```

That event names the killer, the signal, the threshold, and the evidence in
one line. Compare with Episode 1, where no event ever named the kernel.

## 10. Investigation: Evicted vs OOMKilled

```bash
EVICTED_POD=<one of the evicted pods>
kubectl describe pod -n eviction-demo $EVICTED_POD | grep -B2 -A8 -E "^Status:|Reason:|Events:"
```

Key fields: `Status: Failed`, `Reason: Evicted` — versus Episode 1's
`Last State: Terminated, Reason: OOMKilled, Exit Code: 137` on a pod that
was still `Running`.

Node side:

```bash
kubectl describe node $NODE | grep -A 6 "Conditions:"
```

`MemoryPressure` is now `True` — the node's own account of the shortage.
The scheduler sees it too: evicted hogs reschedule to the other worker
(or stay Pending), not back onto the pressured node.

The QoS post-mortem — who died and why:

```bash
kubectl get pods -n eviction-demo -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,STATUS:.status.phase
kubectl get pods -n shopnow     -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,STATUS:.status.phase
```

Hogs: BestEffort → evicted. payment-service: Burstable but usage (~30MB)
below request (64Mi) → survived. **Usage-over-requests is the ranking
metric; BestEffort is always first in line.**

## 11. On the Node: The Kubelet's Side

Two logs, two authors — this is the contrast with Episode 1's `dmesg`:

```bash
ssh -i lab/ssh/id_rsa ubuntu@$WORKER_IP

# 1. The threshold, as the kubelet sees it (we configured this in Section 5)
cat /etc/rancher/k3s/config.yaml

# 2. The kubelet's own eviction log — compare with Episode 1's dmesg
sudo journalctl -u k3s-agent --since "30 min ago" | grep -i evict | tail -20
```

Episode 1's kill was confessed by the **kernel** in `dmesg`. This kill is
confessed by the **kubelet** in `journalctl`. Different author, different
log — the surest proof these are two different mechanisms.

## 12. Metrics: Watching It Happen

The dedicated observability phase. In Grafana, watch the dashboard during
the trigger (Section 8) — screen-record it like Episode 1's sawtooth:

| Panel | What you see |
|---|---|
| **Node Memory Available vs Threshold** | the drain crossing the red 1Gi line — the cliff moment |
| **MemoryPressure condition** | flips to 1 as the threshold crosses |
| **Pod Status: Evicted/Failed** | the eviction appearing, pod by pod |
| **QoS Lens** | hog memory climbing with no limit line; payment-service riding through |
| **Split View** | Ep 1's sawtooth (container vs limit) beside Ep 2's node drain — two killers, one screen |

In Prometheus (http://192.168.1.81:30900), the full query set is in
`promql/queries.md`. The three essentials:

```promql
node_memory_MemAvailable_bytes
kube_node_status_condition{condition="MemoryPressure", status="true"}
kube_pod_status_reason{namespace="eviction-demo", reason="Evicted"}
```

## 13. The Comparison Table

The episode's money shot — run both deaths in one session:

```bash
make demo-ep02   # ends with the side-by-side: re-triggers the Ep1 OOMKill
```

| | OOMKilled | Evicted |
|---|---|---|
| Killer | Linux kernel | kubelet |
| Level | one container (cgroup) | whole pods (node) |
| Trigger | own limit exceeded | node `memory.available` below threshold |
| QoS protection | none — any class dies | everything — BestEffort first |
| Pod after death | Running, RESTARTS +1 | Failed, gone from node |
| Where new pod lands | same node (restart in place) | elsewhere (pressured node repels) |
| Evidence | `memory.events`, `dmesg` | events, node conditions, `journalctl` |
| Metrics | `..._last_terminated_reason{reason="OOMKilled"}` | `kube_pod_status_reason{reason="Evicted"}` |

## 14. Cleanup / Reset

```bash
make cleanup-ep02
# or: episodes/02-oomkilled-vs-evicted/scripts/cleanup.sh
```

This deletes the `eviction-demo` namespace and waits for `MemoryPressure`
to clear. payment-service and the lab stay running.

**Restore the default eviction threshold** on the worker (revert Section 5):

```bash
ssh -i lab/ssh/id_rsa ubuntu@$WORKER_IP
sudo rm /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s-agent
exit
```

Verify: `kubectl describe node $NODE` shows `MemoryPressure False` once the
evicted hogs' memory is freed (metrics drop back within a scrape or two).

---

## Troubleshooting

**No eviction after many rounds** — check whether the threshold is actually
configured (`ps aux | grep kubelet | grep eviction-hard` on the worker), and
whether the node is truly filling (`kubectl top node $NODE`). With the 100Mi
default you need ~3GB; add more rounds or raise hogs.

**Hogs rescheduled onto the other worker and pressure it too** — demo.sh
stops ramping at first eviction; run `make cleanup-ep02` if in doubt.

**Node became unresponsive** — rare (kubelet should evict before system OOM).
Run cleanup from the controller; if the node is unreachable, reboot the VM in
Proxmox and clean up after it recovers.
