# OOMKilled vs Evicted — They Are NOT the Same
## Lab Guide & Runbook

> **Episode 2 of the Kubernetes Under the Hood series.**
> Two pods died last night. One restarted 3 times. The other just vanished.
> Same cluster — two different killers.

**Quick demo:** `make demo-ep02` (guided, interactive) · **Cleanup:** `make cleanup-ep02`

**Two ways to run this demo:**

- **Guided** — `make demo-ep02`: the script walks every step with pauses
  between them (good for a first pass; every command is printed as it runs)
- **Manual, phase by phase** — follow Sections 5–14 below and run each
  command by hand. Better for recording: you control the camera timing at
  every step, pause to explain, and can re-take any phase without rerunning
  the whole script. Every command the script runs is in this guide.

---

## Table of Contents

- [OOMKilled vs Evicted — They Are NOT the Same](#oomkilled-vs-evicted--they-are-not-the-same)
  - [Lab Guide \& Runbook](#lab-guide--runbook)
  - [Table of Contents](#table-of-contents)
  - [1. Episode Overview](#1-episode-overview)
  - [2. Learning Objectives](#2-learning-objectives)
  - [3. Lab Architecture](#3-lab-architecture)
  - [4. Prerequisites](#4-prerequisites)
  - [5. Configure the Eviction Threshold (one-time, reversible)](#5-configure-the-eviction-threshold-one-time-reversible)
    - [What `memory.available` is — and how other clusters ship it](#what-memoryavailable-is--and-how-other-clusters-ship-it)
  - [6. Deploy the Memory Hogs](#6-deploy-the-memory-hogs)
    - [What the hog actually does](#what-the-hog-actually-does)
  - [7. Baseline: The Node Is Healthy](#7-baseline-the-node-is-healthy)
  - [8. Trigger: Fill the Node](#8-trigger-fill-the-node)
  - [9. The Eviction](#9-the-eviction)
  - [10. Investigation: Evicted vs OOMKilled](#10-investigation-evicted-vs-oomkilled)
  - [11. On the Node: The Kubelet's Side](#11-on-the-node-the-kubelets-side)
  - [12. Metrics: Watching It Happen](#12-metrics-watching-it-happen)
    - [Panel 1 — Node Memory Available vs Eviction Threshold (the drain)](#panel-1--node-memory-available-vs-eviction-threshold-the-drain)
    - [Panel 2 — Node Condition: MemoryPressure](#panel-2--node-condition-memorypressure)
    - [Panel 3 — Pod Status: Evicted / Failed](#panel-3--pod-status-evicted--failed)
    - [Panel 4 — QoS Lens: Who Dies First and Why](#panel-4--qos-lens-who-dies-first-and-why)
    - [Panel 5 — Split View: OOMKilled (Ep1) vs Evicted (Ep2)](#panel-5--split-view-oomkilled-ep1-vs-evicted-ep2)
  - [13. The Comparison Table](#13-the-comparison-table)
  - [14. Cleanup / Reset](#14-cleanup--reset)
  - [Troubleshooting](#troubleshooting)

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

### What `memory.available` is — and how other clusters ship it

`memory.available` is the kubelet's eviction signal for node memory — and it
is NOT what `free` reports. The kubelet derives it from cgroupfs:
`node capacity − Σ container working sets`. Working set excludes reclaimable
page cache (`inactive_file`), because the kernel can take that back under
pressure. It is the kubelet's own gauge of real headroom — the node-level
counterpart of Episode 1's container working set. Crossing the threshold sets
the `MemoryPressure` node condition and triggers eviction.

| Platform | `memory.available` threshold | Where it's set |
|---|---|---|
| Upstream kubelet default | `100Mi` | applies only if NO threshold is overridden — changing one zeroes the others unless `mergeDefaultEvictionSettings: true` |
| kubeadm | `100Mi` | upstream default, via `/var/lib/kubelet/config.yaml` |
| EKS | `100Mi` | AMI `bootstrap.sh` → `/etc/kubernetes/kubelet/kubelet-config.json` |
| AKS | `750Mi` pre-1.29, `100Mi` since | managed kubelet config (customizable in preview) |
| GKE | `100Mi` | managed kubelet config (+ large `kubeReserved`) |
| **K3s** | **none** | its disk-only `eviction-hard` override wipes the memory default — hence this section |

For the demo we set the threshold to **1Gi** on the target worker — not the
upstream 100Mi — for headroom: at 100Mi the eviction fires when the node is
nearly dead, while 1Gi triggers while the node is still responsive (on a 4GB
worker we only need to fill ~2GB), the gap on the Grafana graph is big enough
to read, and freeing one hog (~700MB) is enough to recover above the
threshold.

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

First ensure the contrast victim is running — Episode 1's payment-service
(demo.sh does this automatically in its preflight; manually, check and deploy
only if missing):

```bash
kubectl get deployment payment-service -n shopnow &>/dev/null || {
  kubectl apply -f episodes/01-oom-killed/manifests/payment-service.yaml
  kubectl rollout status deployment/payment-service -n shopnow --timeout=180s
}
```

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

Or manually — one loop invocation is ONE round: it asks every Running hog
for +256MB (~768MB on the node with 3 hogs). The execs return immediately —
the hog allocates in the background, 2MB every 2s, so a round finishes over
~4 minutes (paced so Prometheus's 15s scrape interval catches the drain in
Grafana):

```bash
for pod in $(kubectl get pods -n eviction-demo -l app=memory-hog \
             --field-selector status.phase=Running \
             -o jsonpath='{.items[*].metadata.name}'); do
  kubectl exec -n eviction-demo $pod -- python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=256', method='POST')).read().decode(), end='')"
done

# between rounds: watch the drain, then run the loop again
kubectl top node $NODE
```

**Run it 2–3 times.** One round is never enough — repeat the loop, checking
between rounds (Grafana Panel 1 or `kubectl top node $NODE`), until the blue
line crosses the red threshold. The tested run crossed during Round 3; the
exact count depends on the node's starting available memory. demo.sh
automates exactly this (256MB per hog per round, checks between rounds,
stops on the first eviction). `--field-selector status.phase=Running` keeps
the loop away from replacement pods the kubelet rejected at admission during
MemoryPressure (Failed/Evicted — exec into them would error). Once the
threshold is crossed, eviction fires within the kubelet's housekeeping
interval (~10s).

## 9. The Eviction

When `memory.available` crosses the threshold, the kubelet acts within its
housekeeping interval (~10s). Watch for it:

```bash
kubectl get pods -n eviction-demo -w
```

What you'll see (verified on the lab cluster — the `Evicted` line is caught
in the brief window before the display flips; see the quirk below):

```
NAME                          READY   STATUS    RESTARTS   AGE
memory-hog-6944568f56-dr7jj   0/1     Evicted   0          14m
memory-hog-6944568f56-q92f7   1/1     Running   0          14m
memory-hog-6944568f56-zj4xg   1/1     Running   0          14m
```

**Status transitions: the victim goes `Running → Evicted` directly.** No
`Pending`, no restart counter — the kubelet marks the POD itself `Failed`
with `reason: Evicted`. `Pending` belongs to replacement pods — each new hog
flashes `Pending` for a few seconds, then flips to `Evicted` (rejected at
admission, during the pressure window) or to `Running` (once the window
clears). Watch with `-w` to catch the flips.

**Display quirk — known upstream regression (kubernetes/kubernetes#105467):
the STATUS column flips `Evicted → Error` seconds after the kill, and stays
there.** The kubelet writes `Failed/Evicted` first; the container's
last-known terminated state (exit 137, reason `Error`) syncs moments later
and, being more recent, takes precedence in kubectl's STATUS column. The
pod's STORED verdict never changes — `Failed` / `reason: Evicted` with the
killer's message:

```bash
kubectl get pod -n eviction-demo $VICTIM \
  -o jsonpath='{.status.phase} | reason={.status.reason} | msg={.status.message}{"\n"}'
# Failed | reason=Evicted | msg=The node was low on resource: memory. ...
```

So: catch `Evicted` in the first seconds with `-w`, or read it from
reason/message anytime. A genuine `Error` POD state — container died, pod
stays Running and restarts — is Episode 1's signature; here `Error` is just
the container's death mask over an `Evicted` verdict.

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

**Which door the replacement hits depends on timing.** The kubelet also
taints the node (`node.kubernetes.io/memory-pressure:NoSchedule`) the moment
the condition sets. Replacements arriving after the taint lands never get
scheduled at all — they sit `Pending` with FailedScheduling events:

```
Warning  FailedScheduling  default-scheduler  0/3 nodes are available: 1
node(s) had untolerated taint(s), 2 node(s) didn't match Pod's node
affinity/selector.
```

Same lesson, different door: the pressured node repels BestEffort through
the scheduler's taint instead of the kubelet's admission check. Either way,
the replacement waits out the ~5-minute window, then runs on the same node.

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

**Timing: the ×N pile builds AFTER the eviction.** The ranking line appears
the moment the threshold crosses; the rejection lines accumulate over the
NEXT ~5 minutes, one per replacement attempt. Grep immediately after the
eviction and you'll see only the ranking line — re-run it every minute or so
and watch ×N grow. The count and the Ki numbers differ from run to run.

Count the two kinds of corpses (useful when narrating):

```bash
kubectl get pods -n eviction-demo -o jsonpath='{range .items[*]}{.status.message}{"\n"}{end}' \
  | grep -c "low on resource"     # ranking-evicted (the eviction manager's kill)
kubectl get pods -n eviction-demo -o jsonpath='{range .items[*]}{.status.message}{"\n"}{end}' \
  | grep -c "Pod was rejected"    # admission-rejected (the churn loop)
```

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
during the ~5-minute pressure window they're repelled at one of two doors:
bounced between "scheduled onto the node" and "rejected at kubelet
admission" (the churn loop from Section 9), or held `Pending` by the
scheduler's memory-pressure taint (FailedScheduling: "untolerated taint").
Once the transition period expires and the condition clears, a replacement
runs normally on the same node. The pressured node repels its victims —
at the scheduler's taint AND the kubelet's admission door.

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

The dedicated observability phase. The dashboard
("Episode 2 — Eviction Investigation", uid `ep02-evict`) has five panels.
Here is each one — what it shows, the query behind it, how it works, and
WHEN to show it in the demo:

### Panel 1 — Node Memory Available vs Eviction Threshold (the drain)

```promql
node_memory_MemAvailable_bytes
1024 * 1024 * 1024        # red dashed line: the configured 1Gi threshold
```

**How it works:** node-exporter reads `MemAvailable` from `/proc/meminfo` on
every node — a close proxy for the kubelet's `memory.available` signal (the
kubelet computes it as node capacity minus container working sets from
cgroupfs, excluding reclaimable page cache — not `/proc/meminfo`; see
Section 5). The red line is the threshold we configured in Section 5.
**When the blue line crosses the red line, eviction fires.**

**Show it:** Section 7 (baseline — the gap above the line), Section 8
(the drain), Section 9 (the crossing = the cliff moment). Narration Phases
4-6. This is the episode's signature graph — screen-record the whole drain.

### Panel 2 — Node Condition: MemoryPressure

```promql
kube_node_status_condition{condition="MemoryPressure", status="true"}
```

**How it works:** kube-state-metrics exposes node conditions as 0/1. The
kubelet sets the condition when the threshold crosses — and it stays `1` for
~5 minutes (`evictionPressureTransitionPeriod`) even after the hogs' memory
is freed. During that window the kubelet rejects new BestEffort pods at
admission (the churn loop from Section 9).

**Show it:** Section 9 (flips to 1 at the crossing), Section 10 (still True
during the investigation), Section 14 cleanup (flips back to 0 — the
full-circle closing shot). Narration Phases 6-7.

### Panel 3 — Pod Status: Evicted / Failed

```promql
kube_pod_status_reason{namespace="eviction-demo", reason="Evicted"}
kube_pod_status_phase{namespace="eviction-demo", phase="Failed"}
```

**How it works:** kube-state-metrics maps `pod.status.reason` and
`pod.status.phase` to 0/1 series. ONE line steps to 1 — the ranking kill.
The rest of the Evicted pile steps up in a burst — the admission rejections
across the 5-minute window. Note what's missing: no restart counter. Evicted
pods don't restart — they get replaced.

**Show it:** Section 9 (the eviction appearing), Section 10 (the corpse
pile). Narration Phase 7 [11:15].

### Panel 4 — QoS Lens: Who Dies First and Why

```promql
sum by (namespace) (container_memory_working_set_bytes{namespace=~"eviction-demo|shopnow", container!=""})
```

**How it works:** cAdvisor reports per-container working set; summed by
namespace it becomes the two contenders. `eviction-demo` climbs into the
gigabytes with NO ceiling (BestEffort — no limit line to hit);
`shopnow` stays flat at ~30MB (Burstable, usage below request). This panel
IS the ranking, visualized.

**Show it:** Section 8 (climbing during the drain), Section 10 (the QoS
post-mortem). Narration Phase 5 [7:30], Phase 7 [11:45], Phase 8.

### Panel 5 — Split View: OOMKilled (Ep1) vs Evicted (Ep2)

```promql
container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}   # red dashed 128Mi
sum by (pod) (container_memory_working_set_bytes{namespace="eviction-demo", container!=""})
```

**How it works:** Episode 1's story (working set climbing its 128Mi limit —
the sawtooth) beside Episode 2's (hogs climbing with no limit at all). Two
killers, one screen. It lights up fully when Section 13 re-triggers the
OOMKill.

**Show it:** Section 13 (the money shot — Step 7). Narration Phase 7
[12:00] sets it up, Phase 10 pays it off.

In Prometheus (http://192.168.1.81:30900), the full query set is in
`promql/queries.md`. The three essentials:

```promql
node_memory_MemAvailable_bytes
kube_node_status_condition{condition="MemoryPressure", status="true"}
kube_pod_status_reason{namespace="eviction-demo", reason="Evicted"}
```

## 13. The Comparison Table

The episode's money shot — run both deaths in one session.

**Guided:** `make demo-ep02` ends with this step automatically.

**Manual** — re-trigger Episode 1's OOMKill (the kernel, per-container),
then compare:

```bash
# payment-service's limit is 128Mi — feed it 200MB with the same gradual
# 2MB/2s ramp; the kernel SIGKILLs it ~2–4 min in
PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n shopnow "$PS_POD" -- python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=200', method='POST')).read().decode(), end='')"

# wait ~2–4 min for the kernel to kill it, then the side-by-side:
kubectl get pods -n shopnow -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason
kubectl get pods -n eviction-demo -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,REASON:.status.reason
```

Expected: payment-service `Running` with RESTARTS +1 and
`LAST-REASON: OOMKilled` (verified: 8 → 9) — versus the hogs'
`Failed / Evicted` corpses.

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
