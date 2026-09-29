# Episode 3 — PromQL Queries: Diagnosing an OOMKill

The runbook's metrics layer, in query form. All against the lab's
Prometheus (http://192.168.1.81:30900 — any node IP).

---

## Triage (confirm the family)

### 1. Was the last death an OOMKill?

```promql
kube_pod_container_status_last_terminated_reason{namespace="shopnow", reason="OOMKilled"}
```

`1` = the API-visible verdict, straight from kube-state-metrics. This is
the metric version of `kubectl describe`'s `Last State: OOMKilled` — useful
when the pod is already gone from `kubectl get` view.

### 2. The contrast: CrashLoopBackOff (a DIFFERENT family)

```promql
kube_pod_container_status_waiting_reason{namespace="crashloop-demo", reason="CrashLoopBackOff"}
```

`1` = the app is failing to start (restart backoff). Same pod list, same
"pod is broken" symptom — completely different diagnosis path. Triage
first, investigate second.

### 3. Restart counters (the heartbeat of "dying repeatedly")

```promql
kube_pod_container_status_restarts_total{namespace=~"shopnow|crashloop-demo"}
```

Watch both climb — payment-service steps once per OOMKill; crashy steps
every backoff cycle (10s, 20s, 40s...).

## The Autopsy (how close, how fast)

### 4. Working set vs limit — the final minutes

```promql
container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
```

```promql
container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}
```

Run together: the climb to the ceiling and the cliff at the kill. This IS
the Episode 1 graph — now read diagnostically: **how long was the runway?**

### 5. Percent of limit (the "how close" number)

```promql
100 * container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
  / container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}
```

The dashboard's gauge panel. Above 90% sustained = your future OOMKill
(alert threshold — Episode 4 wires this up).

### 6. Rate of climb — the leak signature

```promql
deriv(container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[10m])
```

Bytes/second of growth. **Linear positive derivative that never flattens =
leak.** A legit cache warms up and plateaus (derivative → 0). This single
query decides the fix:

| Shape | Diagnosis | Fix |
|---|---|---|
| Linear climb, no plateau | leak | fix the app (cap the cache) |
| Plateau above the limit | under-sized | right-size (p95 + headroom) |
| Step change at deploy | regression | rollback |

### 7. Time-to-limit extrapolation (the anti-pattern math)

```promql
(container_spec_memory_limit_bytes{container="payment-service"}
  - container_memory_working_set_bytes{container="payment-service"})
  / deriv(container_memory_working_set_bytes{container="payment-service"}[10m])
```

Seconds until the pod dies at the current rate. Run it before proposing
"let's just raise the limit" — Episode 4 shows why doubling the limit on a
leak only doubles the runway.

## Node-level cross-checks (when the pod view is contested)

### 8. Did this node see OOM kills at all?

```promql
node_vmstat_oom_kill{instance=~"<worker>.*"}
```

node-exporter's kernel-wide OOM counter (all processes, not just pods) —
the node-level sanity check for "is memory pressure killing things
outside Kubernetes too?"

## Panel-to-story mapping (Episode 3 dashboard)

| Query | Runbook step | Story beat |
|---|---|---|
| 1, 2, 3 | Step 0 triage | the 30-second fork, in metrics |
| 4, 5 | Step 2 autopsy | the cliff + how close it was |
| 6 | Step 2 autopsy | leak signature — the fix decider |
| 7 | Episode 4 preview | the "raising the limit buys N minutes" math |
