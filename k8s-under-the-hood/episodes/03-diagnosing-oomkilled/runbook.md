# OOMKill Diagnosis Runbook
## The printable — pod dead, logs empty, where do you look FIRST?

> The companion to Episode 3. Works for any Kubernetes cluster.
> Design principle: **investigate one layer deeper than you need — never five.**

---

## Step 0 — Triage (30 seconds, before anything else)

```bash
kubectl get pods -A -o custom-columns=\
NS:.metadata.namespace,\
POD:.metadata.name,\
STATUS:.status.phase,\
RESTARTS:.status.containerStatuses[0].restartCount,\
LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason,\
WAITING-REASON:.status.containerStatuses[0].state.waiting.reason
```

| What you see | Family | Open instead |
|---|---|---|
| RESTARTS climbing + `LAST-REASON: OOMKilled` | **Container limit (kernel)** | this runbook |
| `LAST-REASON: Error` + `WAITING-REASON: CrashLoopBackOff` | **App fails to start** | `kubectl logs` (the logs WILL tell you) |
| `STATUS: Failed` + Reason `Evicted` | **Node pressure (kubelet)** | the eviction runbook (Episode 2) |
| Pod `Pending` | Scheduling/storage | scheduler events (`kubectl describe`) |

> **Empty logs are a hint, not a dead end.** SIGKILL kills the process between
> two log lines — an OOMKilled pod CANNOT log its own death.

## Step 1 — API: the after-action report (~10s)

```bash
kubectl describe pod -n <ns> <pod> | grep -B3 -A6 -E "Last State|Reason|Exit Code|Restart Count"
```

Decode: **Exit Code 137 = 128 + 9** — killed by signal 9 (SIGKILL).
`Last State: OOMKilled` names the killer (kernel) and the cause (limit).

**Stop here if:** you just needed to know *what* happened.

## Step 2 — Metrics: leak or legit? (~60s)

```promql
# confirm the verdict
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}

# how close, how fast — in the minutes before death
container_memory_working_set_bytes{namespace="<ns>", pod="<pod>"}
container_spec_memory_limit_bytes{namespace="<ns>", pod="<pod>"}
deriv(container_memory_working_set_bytes{namespace="<ns>", pod="<pod>"}[10m])
```

Read the shape:
- **Linear climb to the limit** → leak signature (fix the app — Episode 4)
- **Plateau at/above the limit** → under-sized for legit load (right-size — Episode 4)
- **Sharp step at a deploy** → new version changed the footprint

**Stop here if:** you need to decide the fix (leak vs size). This layer
answers it.

## Step 3 — Node: the kernel's counter (~2min)

```bash
POD_UID=$(kubectl get pod -n <ns> <pod> -o jsonpath='{.metadata.uid}')
NODE=$(kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.nodeName}')
NODE_IP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

# cgroup path on K3s (QoS-tiered; burstable shown):
CG=/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod${POD_UID//-/_}.slice

ssh -i lab/ssh/id_rsa ubuntu@$NODE_IP "cat $CG/memory.max $CG/memory.events"
```

`oom_kill > 0` = the kernel's own confession, in its own counter.
(Survives container restarts; the per-container scope gets GC'd quickly.)

**Use when:** the pod is gone, dashboards are down, or someone contests
whether it "really" was an OOMKill.

## Step 4 — Kernel: the kill itself (~2min, rarely needed)

```bash
ssh -i lab/ssh/id_rsa ubuntu@$NODE_IP "sudo dmesg -T | grep -i -E 'out of memory|killed process'"
```

The kill record: timestamp, PID, name, the OOM score. For post-mortems
and vendor escalations. If you're here out of curiosity during an
incident, you're procrastinating.

---

## The Evidence Matrix

| Layer | Command | Answers | Cost |
|---|---|---|---|
| Triage | `kubectl get pods` (custom-columns) | which family of death | 5s |
| Logs | `kubectl logs --previous` | CrashLoop only; EMPTY = OOMKill hint | 10s |
| 1 API | `kubectl describe pod` | who (kernel), why (limit), exit 137 | 10s |
| 2 Metrics | `last_terminated_reason`, WS/limit, `deriv()` | leak vs legit, how close | 60s |
| 3 Node | `cat memory.events` | kernel's own counter | 2min |
| 4 Kernel | `dmesg` | the kill itself, timestamped | 2min |

## The Stop Rule

Investigate **one layer deeper than you need**:

| You need to say | Stop at |
|---|---|
| "It OOMKilled" | Layer 1 (API) |
| "It's a leak / it's under-sized" | Layer 2 (Metrics) |
| "Prove the kernel did it" | Layer 3 (memory.events) |
| "Exhibit A for the post-mortem" | Layer 4 (dmesg) |

## After the Diagnosis

- **Leak** → fix the app (cap the cache / free memory). Do NOT just raise the
  limit — that buys time, not a fix (Episode 4 shows the math).
- **Under-sized** → right-size from p95 working set + headroom, alert at 90%.
- **Deploy regression** → rollback beats debugging at 3am.
