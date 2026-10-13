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
│  the workers — demo.sh   │        │  - untouched by the demo  │
│  picks it dynamically)   │        │    (hogs are PINNED to    │
│                          │        │     the target node via   │
│  - 3× memory-hog         │        │     nodeSelector — their  │
│    (BestEffort, no       │        │     replacements can't    │
│     requests/limits)     │        │     land here)            │
│  - memory.available      │        └──────────────────────────┘
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

**This step is REQUIRED — not just a convenience.** K3s's generated kubelet
config only sets disk thresholds (`nodefs.available<5%`, `imagefs.available<5%`)
and does **NOT** monitor `memory.available` at all. Verify on your workers:

```bash
kubectl get --raw /api/v1/nodes/192.168.1.82/proxy/configz \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['kubeletconfig'].get('evictionHard',{}))"
# -> {'imagefs.available': '5%', 'nodefs.available': '5%'}   <- no memory.available!
```

Without a `memory.available` threshold the kubelet will never evict on memory
pressure — the node would march all the way to a system-level OOM instead.
(Upstream kubeadm clusters default to `memory.available<100Mi`; K3s overrides
that whole map with its disk-only defaults.)

For the demo we set the threshold to **1Gi** on the target worker: on a 4GB
worker we only need to fill ~2GB, which is comfortably short of destabilizing
the node.

> This step is **reversible** — Section 14 shows how to restore K3s's default.

The target worker is `192.168.1.82` (what `demo.sh` picks — in this lab node
names ARE their IPs, so the node name doubles as the SSH target):

```bash
NODE=192.168.1.82

ssh -i lab/ssh/id_rsa ubuntu@$NODE

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
exit
```

Verify the kubelet actually picked it up — from the controller, via configz
(the kubelet runs inside the `k3s agent` process on K3s, so the flag does NOT
show up in `ps aux`):

```bash
kubectl get --raw /api/v1/nodes/$NODE/proxy/configz \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['kubeletconfig'].get('evictionHard',{}))"
# -> {'memory.available': '1Gi'}
```

> **Why this matters on camera:** this file IS the eviction threshold. There
> is no API for it — it's kubelet configuration. Point at it in the episode.
>
> **Note:** the `--eviction-hard` flag REPLACES the whole threshold map, so
> while this config is in place only `memory.available` is monitored (the
> disk thresholds are suspended). Fine for the demo; Section 14 restores the
> K3s default.

<details>
<summary>Alternative: keep K3s's disk-only defaults (no memory eviction)</summary>

Not viable: with no `memory.available` threshold the kubelet never evicts on
memory pressure — the hogs would drive the node to a system-level OOM (and a
reboot) instead of a clean eviction. Configure the threshold (Section 5).
</details>

## 6. Deploy the Memory Hogs

The manifest has a `__WORKER_NODE__` placeholder; the script substitutes the
node name (discover yours with
`kubectl get nodes -l '!node-role.kubernetes.io/control-plane'`):

```bash
NODE=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
sed "s/__WORKER_NODE__/$NODE/" episodes/02-oomkilled-vs-evicted/manifests/memory-hog.yaml | kubectl apply -f -

kubectl rollout status deployment/memory-hog -n eviction-demo --timeout=180s
kubectl get pods -n eviction-demo -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,QOS:.status.qosClass
```

Note in the output: **QOS: BestEffort**. No requests, no limits. The kernel
will never OOMKill these pods per-container — there is no limit to cross.
Only the node running out can kill them, via the kubelet.

### What the hog actually does

Same app pattern as Episode 1's payment-service — a stdlib-only Python HTTP
server shipped as a ConfigMap mounted into a stock `python:3.12-slim` image
(nothing built, fully reproducible), running as non-root with a read-only
filesystem. Four endpoints:

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | liveness/readiness probe target (always 200) |
| `GET /usage` | current RSS of the process, in MB |
| `POST /allocate?mb=N` | grow memory by N MB — gradually: 2MB chunks, one every 2s, each held in a list so it stays allocated |
| `POST /release` | stop allocating and drop everything held |

**Why gradual pacing?** Prometheus scrapes every 15s. An instant allocation
would be one data point — a vertical line nobody can read. 2MB every 2s
makes the node's memory drain smooth in Grafana, scrape by scrape, so the
crime is visible in real time. Same reason as Episode 1's pacing.

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

What you'll see (verified on the lab cluster):

```
NAME                          READY   STATUS    RESTARTS   AGE
memory-hog-6944568f56-dr7jj   0/1     Evicted   0          14m
memory-hog-6944568f56-q92f7   1/1     Running   0          14m
memory-hog-6944568f56-zj4xg   1/1     Running   0          14m
```

**Surprise #1: the kubelet evicts the MINIMUM it needs to.** It ranks all
BestEffort pods by usage-over-request, evicts the biggest offender — ONE hog
(freed ~700MB) — and the node recovers above the threshold, so the ranking
evictions stop. The other two hogs survive. Eviction is not a massacre; it's
a triage.

**Surprise #2: the churn loop.** The Deployment recreates the dead hog — but
the hogs are pinned to this node via `nodeSelector`, and the node's
`MemoryPressure` condition stays `True` for ~5 minutes
(`evictionPressureTransitionPeriod`). Every replacement that lands during
that window gets REJECTED at kubelet admission and marked `Failed/Evicted`
with a pile-up of corpses:

```
memory-hog-6944568f56-gmt4d   0/1   Evicted   # "Pod was rejected: The node
memory-hog-6944568f56-kzmft   0/1   Evicted   #  had condition: [MemoryPressure]"
... (≈19 of these over the 5-minute window)
```

Then the smoking gun — the ONE event from the ranking eviction:

```bash
kubectl get events -n eviction-demo --sort-by=.lastTimestamp \
  -o custom-columns=REASON:.reason,MESSAGE:.message | grep -i evict
```

```
Evicted   The node was low on resource: memory. Threshold quantity: 1Gi,
          available: 1018844Ki. Container memory-hog was using 704220Ki,
          request is 0, has larger consumption of memory.
Evicted   The node had condition: [MemoryPressure].        <- ×19 (admission rejections)
```

The first event names the killer, the signal, the threshold, AND the ranking
evidence ("using 704220Ki, request is 0") in one message. Compare with
Episode 1, where no event ever named the kernel.

## 10. Investigation: Evicted vs OOMKilled

```bash
# pick the pod with the classic 'low on resource' message — the ranking victim
EVICTED_POD=$(kubectl get pods -n eviction-demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.message}{"\n"}{end}' \
  | grep "low on resource" | head -1 | cut -f1)
kubectl describe pod -n eviction-demo $EVICTED_POD | grep -B2 -A8 -E "^Status:|Reason:|Events:"
```

Key fields: `Status: Failed`, `Reason: Evicted` — versus Episode 1's
`Last State: Terminated, Reason: OOMKilled, Exit Code: 137` on a pod that
was still `Running`.

Node side:

```bash
kubectl describe node $NODE | grep -A 6 "Conditions:"
```

`MemoryPressure` is now `True` — the node's own account of the shortage —
and the kubelet has tainted the node with
`node.kubernetes.io/memory-pressure:NoSchedule`. Because the hogs are pinned
to this node via `nodeSelector`, their replacements have nowhere else to go:
during the ~5-minute pressure window they bounce between "scheduled onto the
node" and "rejected at kubelet admission" (the churn loop from Section 9).
Once the transition period expires and the condition clears, a replacement
runs normally on the same node. The pressured node repels its victims —
through kubelet admission, not just the scheduler.

The QoS post-mortem — who died and why:

```bash
kubectl get pods -n eviction-demo -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,STATUS:.status.phase
kubectl get pods -n shopnow     -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,STATUS:.status.phase
```

Hogs: BestEffort → one evicted by ranking, two survived (the kubelet evicts
the minimum needed). payment-service: Burstable but usage (~30MB) below
request (64Mi) → never touched. **Usage-over-requests is the ranking
metric; BestEffort is always first in line.**

## 11. On the Node: The Kubelet's Side

Two logs, two authors — this is the contrast with Episode 1's `dmesg`:

```bash
NODE=192.168.1.82   # the target worker from Section 5 (node name == IP)
ssh -i lab/ssh/id_rsa ubuntu@$NODE

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
| Where new pod lands | same node (restart in place) | Pending (pressured node repels BestEffort) |
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
NODE=192.168.1.82
ssh -i lab/ssh/id_rsa ubuntu@$NODE
sudo rm /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s-agent
exit
```

Verify via configz that only the K3s disk defaults remain:

```bash
kubectl get --raw /api/v1/nodes/$NODE/proxy/configz \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['kubeletconfig'].get('evictionHard',{}))"
# -> {'imagefs.available': '5%', 'nodefs.available': '5%'}
```

Verify: `kubectl describe node $NODE` shows `MemoryPressure False` once the
evicted hogs' memory is freed (metrics drop back within a scrape or two).

---

## Troubleshooting

**No eviction after many rounds** — check whether the threshold is actually
configured (configz command in Section 5 — `ps aux` will NOT show it; the
kubelet runs inside the k3s agent process), and whether the node is truly
filling (`kubectl top node $NODE`).

**Replacement hogs pile up as Failed/Evicted after the first eviction** —
expected: they're pinned to the pressured node via nodeSelector and get
rejected at kubelet admission during the ~5m
`evictionPressureTransitionPeriod` window (Section 9, Surprise #2). They
run normally once the condition clears. Run `make cleanup-ep02` if in doubt.

**Node became unresponsive** — rare (kubelet should evict before system OOM).
Run cleanup from the controller; if the node is unreachable, reboot the VM in
Proxmox and clean up after it recovers.
