# Episode 1 — PromQL Queries (OOMKilled Investigation)

All queries run against the lab Prometheus (`http://192.168.1.81:30900` — any node IP; LoadBalancer with pinned port, no port-forward needed → Graph tab).

## 1. Memory usage vs. limit (the "cliff" before the kill)

The single most important panel: working set approaching the limit right before the OOMKill.

```promql
container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
```

> `working_set_bytes` is what the kernel counts against the cgroup limit — it's RSS minus inactive file cache. This is the line that "hits the ceiling."

```promql
container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}
```

> The limit (128Mi) as seen by the container. In a normal plot, graph query #1 and this together and watch the gap close.

Combined (usage as % of limit):

```promql
100 * container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
  / container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}
```

## 2. Detect that the container WAS OOMKilled

`kube_pod_container_status_last_terminated_reason` — 1 when the container's last termination was for that reason:

```promql
kube_pod_container_status_last_terminated_reason{namespace="shopnow", reason="OOMKilled"}
```

> This is the K8s-API-visible version of the kill (what `kubectl describe pod` shows as `Last State: Terminated, Reason: OOMKilled`).

## 3. Restart history (how many times it happened)

```promql
increase(kube_pod_container_status_restarts_total{namespace="shopnow"}[30m])
```

> Restarts are a symptom — pair with #2 to attribute them to OOMKills specifically.

## 4. OOM kill events from the kernel's point of view (cAdvisor)

```promql
increase(container_oom_events_total{namespace="shopnow", container="payment-service"}[10m])
```

> cAdvisor exposes the cgroup's `oom_kill` counter — the kernel-level event, independent of what Kubernetes reports.
>
> **Known limitation on this stack (K3s + containerd)**: this counter reads
> `0` for the entire container lifetime, even across a confirmed OOMKill
> (verified: exit 137, `kube_pod_container_status_last_terminated_reason=1`,
> yet `container_oom_events_total` stayed flat at 0 the whole time via
> `query_range`). The kubelet's built-in cAdvisor sources container stats
> through containerd's CRI stats API, which doesn't populate the OOM event
> counter the way a standalone cAdvisor/dockershim would. This isn't
> something fixable in our Prometheus config — it's an upstream gap in
> K3s/containerd's stats plugin. For the real kernel-level confirmation,
> read the cgroup file directly (Layer 3 of the investigation):
> `cat /sys/fs/cgroup/.../memory.events` on the node — the `oom_kill` field
> there is accurate.

## 5. Which node did it die on?

```promql
kube_pod_container_info{namespace="shopnow", container="payment-service"}
```

> Useful to know which VM to SSH into for Layer 3 (cgroup files) and Layer 4 (`dmesg`).

## 6. Post-restart memory (the "it's fine again" moment)

After the OOMKill, the container restarts fresh:

```promql
container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[10m]
```

> Switch the graph to show the last 10 minutes: you'll see memory climb, the kill (line drops), then a fresh low start. The sawtooth of an OOM loop.

---

## Reading the results in the demo flow

| Moment | What you'll see |
|---|---|
| Baseline | working_set ≈ 15–25 MB, limit = 128 MiB |
| After `/allocate?mb=200` | working set rockets past the limit line |
| At the kill | working set line breaks; `last_terminated_reason{reason="OOMKilled"}` → 1 |
| After restart | fresh container, low memory, `restarts_total` +1 |
