# The Life of a Metric — from the Linux Kernel to a Pixel

> **Observability Arc, Episode 01 (Foundations)** · ~16 min
> Every number on your dashboard is evidence in a chain of custody with six
> links. We descend them all — from the pixel you stare at, down to the
> kernel counter where the number was born.
>
> **Status:** In production — full artifact package complete.
> **Predecessors:** none — this is the arc's on-ramp (works standalone;
> Season 1 viewers will recognize the callbacks).
> **Next:** [Episode 02 — The Four Observers](../README.md)

**Quick demo:** `make demo-obs01` · **Cleanup:** `make cleanup-obs01` (no-op — this episode is read-only by design)

**The manual (phase-by-phase, for recording):** [lab-guide.md](lab-guide.md)
**The runnable backbone:** [scripts/demo.sh](scripts/demo.sh)

## The Descent (one data point, six links)

```
LINK 6  pixel        Grafana paints samples as a line (a lie of smoothness)
LINK 5  query        a series = name + labels; PromQL finds it
LINK 4  vault        TSDB: head block, series count, ingestion rate
LINK 3  scrape       pull model, 15s interval, service discovery, up
LINK 2  exposition   the exporter: kernel counters rendered as text
LINK 1  kernel       /proc/meminfo — where the number is born
```

## Artifacts

| File | Purpose |
|---|---|
| `narration.md` | 8 timestamped phases (~16 min), verbatim |
| `storyboard.md` | The chain-ladder visual system + the dot-reveal money shot |
| `lab-guide.md` | The manual: guided vs manual, link-by-link, troubleshooting |
| `demo-flow-mapping.md` | Phase → lab-guide → script step |
| `promql/queries.md` | 10 queries — the chain, link by link |
| `dashboards/life-of-a-metric.json` | 4 panels: the data point, delivery health, vault population, heartbeat |
| `scripts/demo.sh` | Read-only guided descent (curl, PromQL, ssh — zero deploys) |
| `scripts/cleanup.sh` | No-op (uniform make pattern) |
| `metadata.md` | SEO titles/thumbnail/description — the arc's top-of-funnel episode |

## Why This Episode Exists

It's the arc's **on-ramp** for viewers new to observability AND the
foundation every incident episode pays off from (cardinality = link 4's
lever; graph holes = link 3 breaking; the average lie = links 5-6). It's
also the highest-search-volume topic in the arc — "how Prometheus works"
is queried orders of magnitude more than any incident topic.
