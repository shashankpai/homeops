# How do you actually diagnose an OOMKilled Pod?
## Lab Guide & Runbook

> **Episode 3 of the Kubernetes Under the Hood series.**
> It's 9am. A pod restarted overnight. You have five minutes before the
> standup. Where do you look FIRST?

**Quick demo:** `make demo-ep03` (guided, interactive) · **Cleanup:** `make cleanup-ep03`

**The printable:** `runbook.md` — this episode's methodology condensed to one
page (decision tree + commands + stop rule). This guide is the expanded,
runnable version.

**Two ways to run this demo:**

- **Guided** — `make demo-ep03`: the script stages both victims, triggers a
  fresh kill, and walks every layer with pauses between steps (good for a
  first pass; every command is printed as it runs)
- **Manual, phase by phase** — follow Sections 5–12 below and run each
  command by hand. Better for recording: you control the camera timing at
  every step, pause to explain, and can re-take any phase without rerunning
  the whole script. Every command the script runs is in this guide.

---

## Table of Contents

- [1. Episode Overview](#1-episode-overview)
- [2. Learning Objectives](#2-learning-objectives)
- [3. Lab Architecture](#3-lab-architecture)
- [4. Prerequisites](#4-prerequisites)
- [5. Stage the Victims](#5-stage-the-victims)
  - [What crashy actually does](#what-crashy-actually-does)
  - [Trigger the fresh kill](#trigger-the-fresh-kill)
- [6. Triage: The 30-Second Fork](#6-triage-the-30-second-fork)
- [7. The False Leads: Logs Lie in Both Directions](#7-the-false-leads-logs-lie-in-both-directions)
- [8. Layer 1 — The Kubernetes API](#8-layer-1--the-kubernetes-api)
- [9. Layer 2 — Metrics: The Fix Decider](#9-layer-2--metrics-the-fix-decider)
  - [Panel 1 — Triage: OOMKilled vs CrashLoopBackOff](#panel-1--triage-oomkilled-vs-crashloopbackoff)
  - [Panel 2 — Restart Counters (both victims)](#panel-2--restart-counters-both-victims)
  - [Panel 3 — The Autopsy: Working Set vs Limit](#panel-3--the-autopsy-working-set-vs-limit)
  - [Panel 4 — Usage vs Limit (%)](#panel-4--usage-vs-limit-)
  - [Panel 5 — Leak Signature (deriv)](#panel-5--leak-signature-deriv)
- [10. Layer 3 — The Node: The Kernel's Own Counter](#10-layer-3--the-node-the-kernels-own-counter)
- [11. Layer 4 — The Kernel: dmesg, and the Stop Rule](#11-layer-4--the-kernel-dmesg-and-the-stop-rule)
- [12. The Evidence Matrix](#12-the-evidence-matrix)
- [13. Cleanup / Reset](#13-cleanup--reset)
- [Troubleshooting](#troubleshooting)

---

## 1. Episode Overview

Episodes 1 and 2 found the killers. This episode is the **methodology**: a
repeatable, ordered runbook for the day it happens to you — demonstrated on
a fresh kill, with a CrashLoopBackOff contrast pod so the triage fork
(OOMKilled vs Evicted vs CrashLoop) is shown live.

The design principle: **investigate one layer deeper than you need — never
five.** Every layer answers a specific question, and every layer has a
"stop here if..." criterion.

| What you see at triage | Family | Killer | Open instead |
|---|---|---|---|
| RESTARTS climbing + `LAST-REASON: OOMKilled` | container crossed its limit | Linux kernel | **this episode** |
| `LAST-REASON: Error` + `WAITING-REASON: CrashLoopBackOff` | the app fails to start | itself | `kubectl logs` — the logs WILL tell you |
| `STATUS: Failed` + Reason `Evicted` | node-level pressure | kubelet | the Episode 2 runbook |
| Pod `Pending` | scheduling/storage | scheduler | `kubectl describe` events |

## 2. Learning Objectives

By the end of this episode you can:

- Triage a broken pod in 30 seconds, before touching logs
- Explain why empty logs are an OOMKill HINT, not a dead end (SIGKILL
  cannot be logged)
- Decode exit code 137 (128 + 9) and name the two possible SIGKILL senders
- Run the four investigation layers in order, with a stop criterion per layer
- Use `deriv()` to classify leak vs under-sized vs deploy-regression — the
  query that decides the fix
- Read the kernel's own kill counter (`cgroup memory.events`) when the
  pod view is gone or contested
- Say "it OOMKilled" with evidence, in 45 seconds

## 3. Lab Architecture

```
                        ┌──────────────────────────────┐
                        │  k8suth-master (control plane)│
                        │  - K3s server                │
                        │  - Prometheus :30900         │
                        │  - Grafana :30300             │
                        └──────────────────────────────┘
                                      │
        ┌─────────────────────────────┴─────────────────────────────┐
        │                     the crime scene                      │
        │                                                          │
        │  VICTIM 1: shopnow/payment-service (Ep 1, Burstable)     │
        │  - 128Mi limit, fresh OOMKill triggered for this episode  │
        │  - dies at the hands of the KERNEL (restarts in place)    │
        │                                                          │
        │  VICTIM 2: crashloop-demo/crashy (contrast pod)          │
        │  - busybox that exits 1, forever                          │
        │  - CrashLoopBackOff — dies at the hands of ITSELF         │
        │                                                          │
        │  The whole episode: telling these two deaths apart,       │
        │  then investigating the OOMKill down four layers.         │
        └──────────────────────────────────────────────────────────┘
```

Key moving parts:

- **payment-service** (`shopnow` namespace): Episode 1's Burstable workload
  — deployed automatically by demo.sh if missing, then freshly killed so
  the diagnosis is live, not historical
- **crashy** (`crashloop-demo` namespace): the triage-contrast victim —
  looks similar in a pod list, completely different diagnosis path
- Both victims are **staged before triage**, so the fork is shown on real
  corpses, not slides

## 4. Prerequisites

- The lab is up (`make verify` passes), observability stack running
- `kubectl` configured (`export KUBECONFIG=~/.kube/config-k8suth`)
- The diagnosis dashboard imported in Grafana:
  `episodes/03-diagnosing-oomkilled/dashboards/oom-diagnosis.json`
  (dashboard "Episode 3 — OOMKill Diagnosis", uid `ep03-diag`;
  Grafana at http://192.168.1.81:30300, any node IP — admin/admin)
- SSH key for the worker nodes at `lab/ssh/id_rsa` (Layer 3 only)

## 5. Stage the Victims

First ensure the OOMKill victim is running — Episode 1's payment-service
(demo.sh does this automatically in its preflight; manually, check and
deploy only if missing):

```bash
kubectl get deployment payment-service -n shopnow &>/dev/null || {
  kubectl apply -f episodes/01-oom-killed/manifests/payment-service.yaml
  kubectl rollout status deployment/payment-service -n shopnow --timeout=180s
}
```

Then deploy the CrashLoop contrast pod:

```bash
kubectl apply -f episodes/03-diagnosing-oomkilled/manifests/crashloop.yaml

# CrashLoopBackOff takes ~1-2 min to land (restart backoff: 10s, 20s, 40s...)
# — check what the STATUS column shows while it gets there:
kubectl get pods -n crashloop-demo -w
```

You'll see crashy flash `Running` (container starts, prints one line, exits 1
after ~1s), then `Running` again, and within a few cycles the STATUS column
settles on `CrashLoopBackOff` while `kubectl get` still shows the pod itself
as `Running` — the CONTAINER is dying, the POD restarts it. That distinction
( container vs pod) is half the triage lesson.

### What crashy actually does

Deliberately minimal — a single Pod, no Deployment, restartPolicy `Always`,
one busybox container whose command is:

```
echo 'starting up... connecting to dependency... FAILED: exit 1' && sleep 1 && exit 1
```

Every restart prints that one line to stdout and exits 1. Kubernetes
restarts it with exponential backoff (10s, 20s, 40s, capped at 5m) — the
signature `CrashLoopBackOff` waiting state. The logs will always contain
the line above — that's the point: **CrashLoopBackOff logs tell you the
answer; OOMKilled logs tell you nothing.**

### Trigger the fresh kill

Diagnose a NEW death, not a stale one — re-arm the kernel's kill on
payment-service (128Mi limit, allocate 200MB with the same gradual 2MB/2s
ramp from Episode 1):

```bash
PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n shopnow "$PS_POD" -- python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=200', method='POST')).read().decode(), end='')"

# poll until the API confirms the kill (~3-4 min ramp + kill):
for i in $(seq 1 40); do
  if kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null | grep -q OOMKilled; then
    echo "✓ fresh OOMKill ready to diagnose"; break
  fi
  sleep 10
done
```

> **Recording note:** start the fresh kill ~4 minutes before you want to
> film the triage, so the corpse (and its metrics history) are warm.

## 6. Triage: The 30-Second Fork

Before logs, before describe, before anything — one command, with the right
columns (single-quoted: unquoted `containerStatuses[0]` makes zsh abort
with `no matches found`):

```bash
kubectl get pods -A -o 'custom-columns=NS:.metadata.namespace,POD:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason,WAITING-REASON:.status.containerStatuses[0].state.waiting.reason'
```

Expected (our staged crime scene; names/counters vary per run):

```
NS              POD                             STATUS    RESTARTS   LAST-REASON    WAITING-REASON
crashloop-demo  crashy                          Running   7          Error           CrashLoopBackOff
shopnow         payment-service-7d9c6b5f4-x2k8p Running   4          OOMKilled
```

Read it like this:

- **payment-service**: RESTARTS climbing + `LAST-REASON: OOMKilled` →
  container crossed its cgroup limit → the KERNEL → **this episode's path**
- **crashy**: `WAITING-REASON: CrashLoopBackOff` → the app fails to start →
  ITSELF → logs will answer it in one command
- (Episode 2's fork, from memory: `STATUS: Failed` + `Evicted` → the KUBELET)

30 seconds, zero investigation commands, and you already know WHICH layer
to investigate and WHICH runbook to open.

## 7. The False Leads: Logs Lie in Both Directions

Every instinct says "check the logs" — so check them, and learn the trap.

**The OOMKilled victim** (`--previous` = the last dead container instance):

```bash
kubectl logs -n shopnow $PS_POD --previous | tail -5
```

No exception. No stack trace. Not even a goodbye. If you're lucky, the
startup banner from the previous life. Empty logs on a dead pod FEEL like
missing evidence — they ARE the evidence: **SIGKILL cannot be caught,
handled, or logged.** The process died between two write calls to stdout.
Empty logs point straight at an OOMKill.

**The CrashLoop victim** (looks similar in the pod list!):

```bash
kubectl logs -n crashloop-demo crashy --previous | tail -3
```

```
starting up... connecting to dependency... FAILED: exit 1
```

Complete opposite: the logs TELL you the answer — an app problem. Same pod
list, same "broken" status, opposite debugging paths.

**The rule: triage FIRST (Section 6), THEN logs — never logs-first.**
Logs-first debugging works for CrashLoopBackOff and fails silently for
OOMKilled.

## 8. Layer 1 — The Kubernetes API

The after-action report:

```bash
kubectl describe pod -n shopnow $PS_POD | grep -B3 -A6 -E "Last State|Reason|Exit Code|Restart Count"
```

Everything you need in one block (verified on the lab in Episode 1's run):

```
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
    Restart Count:  4
```

Decode the exit code — it's arithmetic, not a magic number:

```
Exit Code 137  =  128 + 9
   128 = "killed by a signal"
     9 = SIGKILL — uncatchable, unignorable
```

Only two things send SIGKILL to a container:

| Sender | LAST-REASON says | Next step |
|---|---|---|
| the kernel's OOM killer (container limit) | `OOMKilled` | this episode / Episode 1 |
| the kubelet (liveness probe failures) | something else, with a 137 | check probe events in `describe` |

**Stop-check:** if the question was just "what happened?" — you're done.
Kernel killed it, it crossed the limit, exit 137. Walk into the meeting.
The only reason to go deeper: you must answer *was it a leak or is the pod
under-sized?* — because that decides the fix (Episode 4's fork).

## 9. Layer 2 — Metrics: The Fix Decider

The objective evidence — and the layer that decides the fix. The dashboard
("Episode 3 — OOMKill Diagnosis", uid `ep03-diag`) has five panels. Here is
each one — what it shows, the query behind it, and WHEN to show it:

### Panel 1 — Triage: OOMKilled vs CrashLoopBackOff

```promql
kube_pod_container_status_last_terminated_reason{namespace="shopnow", reason="OOMKilled"}
kube_pod_container_status_waiting_reason{namespace="crashloop-demo", reason="CrashLoopBackOff"}
```

**How it works:** kube-state-metrics exposes the same fields you read at
triage (`lastState.terminated.reason`, `state.waiting.reason`) as 0/1
series. Two lines step to 1 — two victims, two families. The metric version
of the 30-second fork, and it works even when the pod is already gone from
`kubectl get` view.

**Show it:** Section 6 (right after the triage table). Narration Phase 5
[7:06].

### Panel 2 — Restart Counters (both victims)

```promql
kube_pod_container_status_restarts_total{namespace=~"shopnow|crashloop-demo"}
```

**How it works:** the heartbeat of "dying repeatedly." payment-service steps
once per OOMKill; crashy steps every backoff cycle (10s, 20s, 40s — the
staircase IS the exponential backoff). Different step patterns = different
families.

**Show it:** Section 6 (leave it visible while narrating — crashy keeps
stepping for free). Narration Phase 5.

### Panel 3 — The Autopsy: Working Set vs Limit

```promql
container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}   # red dashed 128Mi
```

**How it works:** Episode 1's graph, now read diagnostically: the climb to
the ceiling, the cliff at the kill. The questions it answers: how long was
the runway? how close did it get? **When the blue line touches the red
line, the kill is already decided.**

**Show it:** Section 9 (the autopsy segment). Narration Phase 5 [7:28] —
this is the screen-recorded history from the fresh kill in Section 5.

### Panel 4 — Usage vs Limit (%)

```promql
100 * container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
  / container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}
```

**How it works:** the "how close" number. Sustained above 90% (the orange
threshold) = your future OOMKill — this gauge is the threshold Episode 4
turns into a firing alert.

**Show it:** Section 9. Narration Phase 5.

### Panel 5 — Leak Signature (deriv)

```promql
deriv(container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[5m])
```

**How it works:** the rate of growth, bytes/second — **the single most
useful query in this episode.** Three shapes, three fixes:

| Shape | Diagnosis | Fix |
|---|---|---|
| linear climb, never flattens | **leak** | fix the app (cap the cache) |
| plateau at/above the limit | **under-sized** | right-size (p95 × headroom) |
| step change at a deploy | **regression** | rollback beats debugging |

**Show it:** Section 9, full-screen — the fix decider. Narration Phase 5
[8:00]. This panel is the episode's core visual.

In Prometheus (http://192.168.1.81:30900), the full query set is in
`promql/queries.md`. The three essentials:

```promql
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
container_memory_working_set_bytes{namespace="shopnow"}
deriv(container_memory_working_set_bytes{namespace="shopnow"}[10m])
```

**Stop-check:** this layer answers "leak or legit?" — the fix decider.
If you can act on that answer, stop here. The remaining layers exist for
when the pod view is gone or someone contests the verdict.

## 10. Layer 3 — The Node: The Kernel's Own Counter

Use when: the pod was recreated (history gone), dashboards are down, or
someone says "are you SURE it was an OOMKill?" Build the pod's cgroup
slice path from the POD UID (on K3s the cgroup path uses the pod UID, with
dashes translated to underscores; the pod-level slice survives container
restarts, unlike the per-container scope which is GC'd quickly):

```bash
# on the controller
PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
POD_UID=$(kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.metadata.uid}')
NODE_NAME=$(kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.spec.nodeName}')
CG="/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod${POD_UID//-/_}.slice"
echo "$CG"
```

Then SSH to the node and read the kernel's counter (in this lab the node
NAME is its IP — see the Episode 2 lab-guide — so `$NODE_NAME` is also the
SSH target; demo.sh resolves the InternalIP for the general case):

```bash
ssh -i lab/ssh/id_rsa ubuntu@$NODE_NAME

# on the node — the limit, and the kernel's own kill counter:
echo 'memory.max:';     cat $CG/memory.max
echo 'memory.events:';  cat $CG/memory.events
exit
```

Expected (Episode 1's verified run on this lab):

```
memory.max:
134217728
memory.events:
  low 0
  high 0
  max 20
  oom 1
  oom_kill 4
  oom_group_kill 1
```

`oom_kill > 0` is incremented by the kernel, in the kernel's own data
structure — nobody else writes to it. A signed confession. (In our
threaded demo app the kernel's oom.group flag takes the whole group down,
hence 4 — the point is the counter is NON-ZERO and only the kernel writes
it.)

**Stop-check:** this layer is proof, priced at ~2 minutes and one SSH
session. Below it lies exactly one layer — for post-mortem exhibits only.

## 11. Layer 4 — The Kernel: dmesg, and the Stop Rule

The deepest evidence — the kill record itself (timestamp, PID, name, OOM
score) — for post-mortems and vendor escalations:

```bash
ssh -i lab/ssh/id_rsa ubuntu@$NODE_NAME
sudo dmesg -T | grep -i -E 'out of memory|killed process' | tail -5
exit
```

If you're reading dmesg during an active incident out of curiosity — you're
procrastinating in a very technical costume. So the runbook's soul, the
stop rule — investigate ONE layer deeper than you need:

| You need to say | Stop at |
|---|---|
| "It OOMKilled" | Layer 1 (API) |
| "It's a leak / under-sized" | Layer 2 (Metrics) |
| "Prove the kernel did it" | Layer 3 (memory.events) |
| "Exhibit A for the post-mortem" | Layer 4 (dmesg) |

## 12. The Evidence Matrix

The whole runbook in one table — every row run live in this episode:

| Layer | Command | Answers | Cost |
|---|---|---|---|
| Triage | `kubectl get pods` (custom-columns) | which family of death | 5s |
| Logs | `kubectl logs --previous` | CrashLoop only; EMPTY = OOM hint | 10s |
| 1 API | `kubectl describe pod` | who (kernel), why (limit), exit 137 | 10s |
| 2 Metrics | WS/limit, `deriv()` | leak vs legit, how close | 60s |
| 3 Node | `cat memory.events` | kernel's signed confession | 2min |
| 4 Kernel | `dmesg` | the kill itself, timestamped | 2min |

The payoff: when someone asks "what happened to the payment service?", you
say — *"Kernel killed it at 3:14am, container crossed its 128-meg limit,
exit 137, working set climbing linearly for six hours — it's a leak, and
here's the trend graph."* Forty-five seconds, every claim evidenced.

The printable version (same rows, all commands, ready for your wiki):
**`runbook.md`** in this directory.

## 13. Cleanup / Reset

```bash
make cleanup-ep03
# or: episodes/03-diagnosing-oomkilled/scripts/cleanup.sh
```

This deletes the `crashloop-demo` namespace (crashy). payment-service and
the lab stay running — its restart counter keeps the episode's kills as
evidence; that's history, not a problem. To also reset payment-service:

```bash
kubectl delete deployment payment-service -n shopnow
# re-run any episode's demo to redeploy it fresh (restart counter back to 0)
```

---

## Troubleshooting

**`kubectl logs --previous` says `previous terminated container not found`** —
`--previous` needs a dead container instance to read. Either the pod hasn't
died yet (payment-service before the Section 5 kill lands) or it was
recreated since. For payment-service, re-trigger the kill (Section 5); for
crashy, wait ~10s after its first exit.

**crashy shows `Running`/`Completed`-ish states, not `CrashLoopBackOff` yet** —
timing: the label is the WAITING reason and only appears once the backoff
grows past a restart cycle or two. First cycles: `Running` → exit 1 →
`Running`... Watch `kubectl get pods -n crashloop-demo -w` for ~90s, or
read the waiting reason directly:
`kubectl get pod -n crashloop-demo crashy -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}'`.

**`no matches found` on the triage command (zsh)** — the unquoted
`containerStatuses[0]` glob got you: zsh treats `[0]` as a character class.
The commands in this guide are single-quoted for exactly this reason —
keep the quotes when you adapt them.

**The kill never lands after `/allocate`** — the ramp is gradual
(2MB/2s), so 200MB takes ~3-4 min; also make sure you're exec-ing the
CURRENT pod instance — if the pod restarted mid-ramp (an earlier kill),
`$PS_POD` may point at a corpse. Re-fetch the pod name and re-run.

**cgroup path is empty / `oom_kill 0`** — you built the path from a pod
that was recreated (new POD UID = new slice). Re-fetch POD_UID for the
CURRENT pod, and use the pod-level slice (`kubepods-burstable-pod...`),
not the per-container scope (GC'd fast). Verify with
`ls /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/` on the node.

**Node SSH fails** — the lab's SSH key is `lab/ssh/id_rsa` from the repo
root; run from there or use the absolute path. (Node names are IPs in this
lab — `ssh -i lab/ssh/id_rsa ubuntu@192.168.1.82`.)
