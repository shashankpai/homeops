# Episode 2 — PromQL Queries: OOMKilled vs Evicted

All queries assume the lab's Prometheus (http://192.168.1.81:30900 — any node
IP works) with node-exporter, kube-state-metrics, and cAdvisor scraped at 15s.

Replace `<worker>` with the target node's instance/label values — discover
with the label finders at the bottom.

---

## The Drain (the episode's signature graph)

### 1. Node memory available — the signal kubelet actually watches

```promql
node_memory_MemAvailable_bytes{instance=~"<worker>.*"}
```

This is `memory.available` — the eviction signal. Watch it fall as the hogs
ramp. The kubelet compares THIS number against its eviction threshold
(`memory.available<1Gi` on the configured target worker — lab-guide §5).
Note: stock K3s has NO memory threshold at all (only disk signals) — without
Section 5 the kubelet would never evict on memory pressure. When the number
crosses the threshold, eviction fires. This is the mirror image of Episode
1's container working-set climb toward its limit.

### 2. The same graph with the eviction threshold as a line

```promql
node_memory_MemAvailable_bytes{instance=~"<worker>.*"}
```

In Grafana, add a second query as a red dashed threshold line:

```promql
1024 * 1024 * 1024   # 1Gi — matches eviction-hard=memory.available<1Gi
```

(Use `100 * 1024 * 1024` for the 100Mi default.) The moment the blue line
crosses the red line, the kubelet evicts. That crossing is the episode's
cliff moment.

### 3. Where the memory went — hog working set

```promql
container_memory_working_set_bytes{namespace="eviction-demo", container="memory-hog"}
```

The hogs' memory climbing in 2MB steps. Note there is NO limit line to hit —
BestEffort pods have none. Nothing kills them per-container; only the NODE
running out is what matters.

---

## The Eviction (the Kubernetes-visible truth)

### 4. Pod status reason: Evicted

```promql
kube_pod_status_reason{namespace="eviction-demo", reason="Evicted"}
```

Flips to `1` when the kubelet evicts a pod. This is what
`kubectl get pods` renders as `STATUS: Evicted` — the API-visible verdict,
sourced from `pod.status.reason`.

### 5. Pod phase: Failed (evicted pods never restart in place)

```promql
kube_pod_status_phase{namespace="eviction-demo", phase="Failed"}
```

Contrast with Episode 1: the OOMKilled pod stayed `Running` (only its
RESTARTS counter incremented). The evicted pod goes `Failed` and is deleted
from the node — the Deployment recreates it, but the hogs are pinned to the
pressured node via nodeSelector, so replacements bounce off kubelet
admission during the ~5m pressure window (the churn loop).

### 6. Node condition: MemoryPressure

```promql
kube_node_status_condition{condition="MemoryPressure", status="true"}
```

`1` = the node is under memory pressure. Appears when the threshold crosses;
stays true for ~5 minutes (`evictionPressureTransitionPeriod`) even after
the hogs' memory is freed — during that window the kubelet rejects new
BestEffort pods at admission (the churn loop), then the condition clears.

---

## The Ranking (who dies first and why)

### 7. Usage over requests — the eviction ranking metric

```promql
container_memory_working_set_bytes{namespace="eviction-demo", container="memory-hog"}
  - on(pod) kube_pod_container_resource_requests{namespace="eviction-demo", resource="memory"}
```

The kubelet ranks eviction candidates by usage ABOVE their requests.
BestEffort pods (no requests) are at maximum risk by definition — their whole
footprint is "over request". This is why the hogs die and the Burstable
payment-service (usage ~30MB vs 64Mi request — BELOW request) survives.

### 8. The survivors, by QoS — the QoS-lens panel

```promql
sum by (namespace) (container_memory_working_set_bytes{namespace=~"eviction-demo|shopnow", container!=""})
```

`eviction-demo` (BestEffort hogs) drains the node; `shopnow` (Burstable
payment-service) rides through the eviction. Same cluster, same pressure,
different fates — QoS is the difference.

---

## The Contrast (Episode 1 vs Episode 2, side by side)

### 9. The OOMKilled verdict (Episode 1's metric)

```promql
kube_pod_container_status_last_terminated_reason{namespace="shopnow", reason="OOMKilled"}
```

### 10. The restart counter — OOMKilled pods restart, evicted pods don't

```promql
kube_pod_container_status_restarts_total{namespace="shopnow"}
```

Run 9 and 10 next to 4 and 5 during the side-by-side segment: the
payment-service OOMKill shows `reason=OOMKilled` + `restarts` stepping up
while staying `Running`; the hogs show `reason=Evicted` + `phase=Failed` with
NO restart count — a different pod entirely is created elsewhere.

---

## Label finders (run these first)

```promql
# node-exporter instance labels (one per node)
up{job="node-exporter"}
```

```promql
# all nodes kube-state-metrics knows about
kube_node_info
```

```promql
# confirm the target worker's current condition state
kube_node_status_condition{condition="MemoryPressure"}
```

---

## Panel-to-story mapping

Dashboard panels (lab-guide §12 has the full panel-by-panel reference):

| Dashboard panel | Queries | Demo step (lab-guide) | Narration phase | Story beat |
|---|---|---|---|---|
| 1 — Mem Available vs Threshold | 1, 2 | §7 baseline, §8 trigger, §9 crossing | 4, 5, 6 | The drain toward the red line — the cliff moment |
| 2 — MemoryPressure condition | 6 | §9, §10, §14 cleanup | 6, 7 | Flips to 1 at crossing; ~5m window; clears at cleanup |
| 3 — Pod Status: Evicted/Failed | 4, 5 | §9, §10 | 6, 7 | The ranking kill + the admission-rejection pile |
| 4 — QoS Lens | 3, 8 | §8, §10 | 5, 7, 8 | Hogs climb with no ceiling; payment-service rides through |
| 5 — Split View | 9, 10 | §13 money shot | 7 setup, 10 payoff | Ep1 sawtooth vs Ep2 no-limit — two killers, one screen |
