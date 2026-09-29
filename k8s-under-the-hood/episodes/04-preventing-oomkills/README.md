# Episode 4 — How do you prevent Kubernetes OOMKills?

> **Status:** In production — full artifact package complete
> (narration, prevention checklist, lab guide, demo scripts, dashboard, metadata)
> **Predecessors:** [Episode 1 — the 5-layer OOMKill descent](../../README.md) ·
> [Episode 3 — the diagnosis runbook](../03-diagnosing-oomkilled/README.md)
>
> **Quick demo:** `make demo-ep04` · **Cleanup:** `make cleanup-ep04`
> **The printable:** [prevention-checklist.md](prevention-checklist.md)
> **Alert rules:** wired into `lab/observability/prometheus.yaml`
> (MemoryNearLimit at 90% of limit + OOMKilledRecently)

## Objective

Close Season 1 with the engineering answer: now that you know who kills
pods and how to diagnose it — how do you make sure it never pages you?

## Core Content (what we intend to show)

1. **Right-sizing from real data** — p95/p99 working set + headroom as
   the limit; the working-set-vs-limit Grafana panel as the sizing tool;
   why "just double the limit" is an anti-pattern (it hides leaks)
2. **The requests question** — what requests actually buy you
   (scheduling + eviction ranking, from Episode 2), and when
   requests == limits (Guaranteed) is worth it
3. **Leak detection with trends** — PromQL rate-of-change queries that
   distinguish a leak from a cache warm-up; alerting at 90% of limit
   with meaningful lead time
4. **VPA and its traps** — what the Vertical Pod Autoscaler does and
   doesn't do for you
5. **Load testing before prod** — reproducing the Episode 1 kill
   deliberately in CI/staging as a pre-deploy gate
6. **The prevention checklist** — the printable season-finale artifact

## Planned Artifacts

- `manifests/` (right-sized payment-service variants: bad → good)
- `promql/queries.md` — sizing + leak-detection + alert queries
- `alerts/` — example PrometheusRule (90%-of-limit alert)
- `narration.md` / `storyboard.md` / `metadata.md` /
  `prevention-checklist.md` (the takeaway artifact)

## Format

~15–20 min, demo-driven: show a mis-sized pod, diagnose with Episode 3's
runbook, right-size it with metrics, prove the fix survives the same load
that killed it before. Full-circle season ending.
