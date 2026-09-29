# OOMKill Prevention Checklist
## The printable — how to make sure the kernel never pages you again

> The companion to Episode 4 (season finale). Follow in order.
> Principle: **prevention is an engineering exercise, not a bigger number.**

---

## 1. MEASURE — from data, not vibes

```promql
# p95 / p99 working set over a representative window (use days in prod)
quantile_over_time(0.95, container_memory_working_set_bytes{namespace="<ns>", pod="<pod>"}[24h])
quantile_over_time(0.99, container_memory_working_set_bytes{namespace="<ns>", pod="<pod>"}[24h])
```

- Use a window that includes your worst legit traffic (peak hours,
  batch runs, deploys)
- Note the **baseline** (idle RSS) and the **peak** separately — you'll
  size for the peak, and the gap tells you the app's real footprint

## 2. CLASSIFY — leak or legit? (this decides everything)

```promql
deriv(container_memory_working_set_bytes{namespace="<ns>", pod="<pod>"}[10m])
```

| Shape | Diagnosis | Fix |
|---|---|---|
| Linear climb, never flattens | **Leak** | fix the app — go to 3a |
| Plateau at/above limit | **Legit load, under-sized** | go to 3b |
| Step change at a deploy | **Regression** | rollback first, analyze later |

## 3. FIX THE RIGHT THING

**3a. Leaks are app bugs. No YAML fixes a leak.**
- Cap the cache / bound the retention / free on idle
- Raising the limit on a leak = `time-to-limit = (limit − WS) / growth_rate`
  — you buy minutes, not a fix. The pod still dies, just at 3am instead
  of 3pm.
- Catch leaks pre-prod with a soak test: run the load for hours in
  staging and watch `deriv()` — it should trend to zero

**3b. Right-size legit workloads.**
- `limit ≈ peak working set × 2` (headroom for bursts, fragmentation,
  deploys), rounded to a sane value
- `requests`: what the scheduler may rely on AND what protects you from
  eviction (Episode 2: usage-over-requests is the kubelet's ranking)
- For critical paths: `requests == limits` (**Guaranteed QoS**) —
  eviction-proof and a hard scheduling promise

## 4. ALERT — page BEFORE the kernel does

```promql
container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.90
```

- 90% of limit, `for: 5m` in production (the lab uses `for: 1m` for
  demo speed) — the lab's rules: `lab/observability/prometheus.yaml`
  (`MemoryNearLimit`, `OOMKilledRecently`)
- Pair it with a restart alert: `increase(kube_pod_container_status_restarts_total[10m]) > 2`
- The goal is lead time: a human with 20 minutes beats a kernel with a
  SIGKILL every time

## 5. PROVE — reproduce, then survive

- Load-test the same load that killed the pod (Episode 4's arc:
  `mb=200` killed it at 128Mi; the right-sized pod survives it at 512Mi)
- Do this BEFORE prod, not after — the kill is cheap in staging and
  expensive in production

## 6. REVIEW — VPA, with eyes open

- The Vertical Pod Autoscaler **recommends** from p95+headroom (exactly
  the math in step 3b) — useful for stateless fleets
- Traps: it **restarts** pods to apply new sizes (disruption), and it
  will happily right-size you INTO a leak (it treats leaks as demand)
- Human decides, VPA recommends

---

## The Season-1 Summary (all four episodes)

| Episode | Question it answers |
|---|---|
| 1 — the kill | WHO killed my pod? (the kernel, via cgroups) |
| 2 — the other killer | Who's the OTHER killer? (the kubelet, via eviction) |
| 3 — the runbook | HOW do I find out, fast and repeatably? |
| 4 — the fix | HOW do I make sure it never happens again? |
