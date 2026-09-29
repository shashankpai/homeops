# Episode 4 — PromQL Queries: Preventing OOMKills

The prevention episode's query set — sizing, leak detection,
extrapolation, and alert validation. Against the lab's Prometheus
(http://192.168.1.81:30900 — any node IP).

---

## Sizing (measure before you set numbers)

### 1. p95 / p99 working set — the number to size from

```promql
quantile_over_time(0.95, container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[1h])
```

```promql
quantile_over_time(0.99, container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[1h])
```

(In the demo the window is 1h because the pod is young; production sizing
uses days-to-weeks that include your worst legit traffic.)

### 2. Baseline vs peak — the app's real footprint

```promql
min_over_time(container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[1h])
```

```promql
max_over_time(container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[1h])
```

Baseline ~25MB (idle Python), peak ~225Mi (held cache) → that gap is the
app's working footprint; size the limit for the peak, not the average.

## Classifying (the fix decider, from Episode 3)

### 3. Growth rate — leak signature

```promql
deriv(container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}[5m])
```

Linear positive = leak. Falling to zero = plateau (legit). Step = deploy
regression.

### 4. Time-to-limit — the anti-pattern quantifier

```promql
(container_spec_memory_limit_bytes{container="payment-service"}
  - container_memory_working_set_bytes{container="payment-service"})
  / clamp_min(deriv(container_memory_working_set_bytes{container="payment-service"}[10m]), 1)
```

Seconds until death at the current rate (clamped to ≥1B/s so a flat line
doesn't divide by zero). Run it before anyone proposes raising the limit:
**doubling the limit on a leak doubles the runway, not the fix.**

## Proving the fix (the money-shot queries)

### 5. The bad pod vs the sized pod, side by side

```promql
container_memory_working_set_bytes{namespace="shopnow", container=~"payment-service|payment-sized"}
```

Same load (`mb=200`): bad pod climbs to 128Mi and dies; sized pod climbs
to ~225Mi and STAYS — 44% of its 512Mi limit.

### 6. The survival proof, in restart counters

```promql
kube_pod_container_status_restarts_total{namespace="shopnow"}
```

Bad pod's counter steps up with each OOMKill; the sized pod's stays flat
under the same load. Zero restarts = the fix, quantified.

### 7. Percent of limit — the alert line, visualized

```promql
100 * container_memory_working_set_bytes{namespace="shopnow", container="payment-sized"}
  / container_spec_memory_limit_bytes{namespace="shopnow", container="payment-sized"}
```

Crosses 90% when the demo pushes the sized pod past 461Mi — exactly
where `MemoryNearLimit` fires.

## The Safety Net (alert rules wired into the lab)

The rules live in `lab/observability/prometheus.yaml` (the
`alerts.yml` ConfigMap key — plain Prometheus `rule_files`, no Operator
needed):

| Alert | Expression | Fires when |
|---|---|---|
| `MemoryNearLimit` | `WS / limit > 0.90` for 1m (demo; use 5m in prod) | the pod is 90% of the way to death — with lead time |
| `OOMKilledRecently` | `last_terminated_reason{reason="OOMKilled"} == 1` | a kill already happened — run the Episode 3 runbook |

### 8. Validate the rules are loaded / firing (API checks)

```bash
# rules loaded?
curl -s http://192.168.1.81:9090/api/v1/rules | grep MemoryNearLimit

# alert state (pending -> firing)?
curl -s http://192.168.1.81:9090/api/v1/alerts | grep -A2 MemoryNearLimit
```

## Panel-to-story mapping (Episode 4 dashboard)

| Query | Demo step | Story beat |
|---|---|---|
| 3 | Step 3 | leak signature — the fork |
| 4 | Step 4 | "raise the limit" math — the anti-pattern |
| 5, 6 | Step 6 | same load, survived — the money shot |
| 7 | Step 7 | crossing 90% — the alert firing line |
| 1, 2 | Step 6 (setup) | the sizing math, from measurements |
