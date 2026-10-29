# The Life of a Metric — from the Linux Kernel to a Pixel
## Lab Guide & Runbook

> **Observability Arc, Episode 01 (Foundations).**
> Every number on your dashboard is evidence in a chain of custody with six
> links. Today we descend them all — from the pixel you stare at, down to the
> kernel counter where the number was born.

**Quick demo:** `make demo-obs01` (guided, interactive)

**Zero new infrastructure:** this episode is entirely **read-only** — every
link we trace is already running in your lab (Prometheus, Grafana,
node-exporter). `cleanup-obs01` is a no-op by design.

**Two ways to run this demo:**

- **Guided** — `make demo-obs01`: the script walks every link with pauses
  between steps (good for a first pass; every command is printed as it runs)
- **Manual, link by link** — follow Sections 4–10 below and run each command
  by hand. Better for recording: you control the camera timing at every
  step. Every command the script runs is in this guide.

**The data point we follow:** `node_memory_MemAvailable_bytes` — the same
metric that caught the eviction in Season 1 (Episode 2's drain graph).

---

## Table of Contents

- [1. Episode Overview](#1-episode-overview)
- [2. Learning Objectives](#2-learning-objectives)
- [3. The Chain (architecture)](#3-the-chain-architecture)
- [4. Preflight](#4-preflight)
- [5. Link 6 — The Pixel (Grafana)](#link-6--the-pixel-grafana)
- [6. Link 5 — The Query (PromQL)](#link-5--the-query-promql)
- [7. Link 4 — The Vault (TSDB)](#link-4--the-vault-tsdb)
- [8. Link 3 — The Delivery Run (the scrape)](#link-3--the-delivery-run-the-scrape)
- [9. Link 2 — The Translator (the exposition)](#link-2--the-translator-the-exposition)
- [10. Link 1 — The Origin (the kernel)](#link-1--the-origin-the-kernel)
- [11. The Full Chain + Failure Map](#11-the-full-chain--failure-map)
- [12. Metrics: The Episode Dashboard](#12-metrics-the-episode-dashboard)
- [13. Cleanup](#13-cleanup)
- [Troubleshooting](#troubleshooting)

---

## 1. Episode Overview

Foundations episode: the observability stack *introduced by walking through
it live* — not by slides. One data point, six links, descended backwards the
way Season 1 descended through pod-death layers:

```
LINK 6  pixel        Grafana paints samples as a line (a lie of smoothness)
LINK 5  query        a series = name + labels; PromQL finds it
LINK 4  vault        TSDB: head block, series count, ingestion rate
LINK 3  scrape       pull model, 15s interval, service discovery, up
LINK 2  exposition   the exporter: kernel counters rendered as text
LINK 1  kernel       /proc/meminfo — where the number is born
```

Every link has a failure mode — and each failure is a later episode in the
arc (Section 11 maps them).

## 2. Learning Objectives

By the end of this episode you can:

- Trace any metric on your dashboards back to its origin, link by link
- Explain what a time series IS (name + label set = one unique stream)
- Read the Prometheus exposition format (HELP / TYPE / series lines)
- Explain pull-vs-push and why scrape interval defines your resolution
- Query the vault ABOUT the vault (head series, chunks, ingestion rate)
- Read `up` and `scrape_duration_seconds` — the delivery health pair
- Know which link to suspect when a graph misbehaves (the failure map)

## 3. The Chain (architecture)

```
┌────────────────────────────────────────────────────────────────┐
│  LINK 1: KERNEL          each worker node                       │
│  /proc/meminfo ── MemAvailable (kB) — the kernel's accounting  │
└──────────────────┬─────────────────────────────────────────────┘
                   │ read (hostPath /proc → /host/proc)
┌──────────────────▼─────────────────────────────────────────────┐
│  LINK 2: node-exporter (DaemonSet, hostNetwork, :9100)         │
│  translates kernel counters → exposition text (bytes)          │
└──────────────────┬─────────────────────────────────────────────┘
                   │ LINK 3: SCRAPE (pull, every 15s)
                   │ kubernetes_sd finds pods labeled app=node-exporter
┌──────────────────▼─────────────────────────────────────────────┐
│  LINK 4: TSDB (inside Prometheus, monitoring namespace)        │
│  head block in RAM → chunks flushed to the 5Gi PVC             │
└──────────────────┬─────────────────────────────────────────────┘
                   │ LINK 5: QUERY (PromQL, label-indexed lookup)
┌──────────────────▼─────────────────────────────────────────────┐
│  LINK 6: Grafana :30300 — samples painted as a line            │
│  (every dot = one survived link of custody)                    │
└────────────────────────────────────────────────────────────────┘
```

The lab's actual wiring this episode relies on (all from
`lab/observability/`): the node-exporter DaemonSet (`hostNetwork: true`,
annotation `prometheus.io/port: "9100"`, hostPath `/proc` mounted at
`/host/proc`), and the `node-exporter` scrape job in
`lab/observability/prometheus.yaml` (pod discovery + address rewrite via
relabel_configs).

## 4. Preflight

```bash
# lab up, monitoring namespace healthy
kubectl get pods -n monitoring

# Prometheus reachable (any node IP — LoadBalancer, pinned port 30900)
curl -s http://192.168.1.81:30900/-/healthy

# dashboard imported: "Episode OBS-01 — The Life of a Metric"
#   episodes/observability/01-the-life-of-a-metric/dashboards/life-of-a-metric.json
# Grafana: http://192.168.1.81:30300 (admin/admin)
```

## Link 6 — The Pixel (Grafana)

Open the dashboard and find the "The Data Point" panel
(`node_memory_MemAvailable_bytes`). Now ruin graphs, gently:

- Zoom in until you can see the sampling: **15s between dots** — the line
  is Grafana interpolating between samples
- Between every pair of dots, 15 seconds of reality went unobserved.
  (Season 1 leaned on this: the payment-service ramp was paced 2MB/2s
  *specifically* so the climb would land across multiple dots — faster
  kills die invisibly between scrapes; see Episode 1's payment-service.yaml
  header comment)

**The takeaway:** the pixel is a painting over samples. Grafana stores
nothing — it asks, someone else answers. Who answers?

## Link 5 — The Query (PromQL)

In the Prometheus UI (http://192.168.1.81:30900), run the query and switch
from **Graph** to **Table** — the view that shows what a metric actually is:

```promql
node_memory_MemAvailable_bytes
```

Table output: metric name, labels (`instance`, `job`), one value. That name
plus its full label set is **one time series** — a unique stream of dots.
The labels are the dimensions (which machine, which scrape job).

One family, many series — the multiplication rule that foreshadows the
cardinality episode:

```promql
count(node_memory_MemAvailable_bytes)
```

## Link 4 — The Vault (TSDB)

Prometheus monitors itself (the `prometheus` job scrapes `localhost:9090` —
already in the lab's scrape config). Query the vault about the vault:

```promql
# series currently in the hot head block (memory-resident)
prometheus_tsdb_head_series

# memory-resident chunks (compressed sample runs)
prometheus_tsdb_head_chunks

# the pipeline's heartbeat: samples/second flowing into the vault
rate(prometheus_tsdb_head_samples_appended_total[1m])
```

Notes for narration: series count ≈ memory usage (the lever the cardinality
episode pulls); recent samples serve from the head block in RAM, older ones
from the PVC (`prometheus-data`, 5Gi).

## Link 3 — The Delivery Run (the scrape)

**Prometheus UI → Status → Targets.** Every delivery route: node-exporter
(one target per node — three), kube-state-metrics, the kubelets, cAdvisor,
Prometheus itself. Each row shows endpoint, interval, last scrape, duration.

The delivery health pair — the two metrics every stack should have on a wall:

```promql
up{job="node-exporter"}                    # 1 = last scrape succeeded
scrape_duration_seconds{job="node-exporter"}   # how long the delivery took
```

`up` is written by Prometheus itself per scrape — like a driver signing the
delivery log. When a target gets too heavy, `scrape_duration_seconds` climbs
toward the interval, scrapes fail, and graphs develop holes (episode 07's
topic — taste the foreshadowing here).

Where the target list comes from — service discovery (from
`lab/observability/prometheus.yaml`):

```yaml
- job_name: node-exporter
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app]
      regex: node-exporter
      action: keep
    - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
      regex: ([^:]+)(?::\d+)?;(\d+)
      replacement: $1:$2
      target_label: __address__
```

A new node joins → the DaemonSet plants an exporter → it appears in targets
with **no config change**. That's how the lab's stack self-assembles.

## Link 2 — The Translator (the exposition)

node-exporter runs `hostNetwork`, so its endpoint is the node's own address.
Skip the middleman — read the source directly from your workstation:

```bash
NODE=192.168.1.82   # any worker; node names are IPs in this lab
curl -s http://$NODE:9100/metrics | head -20
```

The exposition format: `# HELP`, `# TYPE`, then series lines — name, labels,
value. Plain text, one endpoint, thousands of lines.

Now find OUR data point:

```bash
curl -s http://$NODE:9100/metrics | grep -A2 MemAvailable
```

```
# HELP node_memory_MemAvailable_bytes Memory information field MemAvailable.
# TYPE node_memory_MemAvailable_bytes gauge
node_memory_MemAvailable_bytes 1.992323072e+09
```

**The key insight:** the exporter is a stateless translator. It remembers
NOTHING — it renders the current truth as text on demand. The time dimension
isn't in the exporter at all: the vault builds the history by sampling this
endpoint every 15 seconds.

## Link 1 — The Origin (the kernel)

node-exporter mounts the host's `/proc` read-only and reads the kernel's
accounting files. SSH to the node and read the SAME file the exporter reads:

```bash
ssh -i lab/ssh/id_rsa ubuntu@$NODE
grep MemAvailable /proc/meminfo
# MemAvailable:    1945588 kB
exit
```

Do the arithmetic: 1,945,588 kB × 1024 = 1.99 GB — the same number the
exporter served, the vault stored, the query found, the pixel painted.
`/proc` is the kernel's API; `MemAvailable` is the kernel's own estimate of
what it could hand out without swapping. The chain even does unit conversion
(kernel kB → Prometheus bytes) — every link assumes the one before it was
honest.

## 11. The Full Chain + Failure Map

Walk it forward — the direction the data flows:

```
kernel counter → exporter → scrape (15s) → TSDB → query → pixel
```

| Link | How it breaks | The episode |
|---|---|---|
| exporter → scrape | too many series to serialize — scrape timeouts | 04 — Cardinality Explosion |
| TSDB | too many series to store — Prometheus OOMKilled by its own limit | 04 — Cardinality Explosion |
| scrape → vault | target down, samples stop | 07 — Why Your Graph Has Holes |
| the observers | four sources, three different numbers | 08 — Three Numbers, One Pod |
| query → pixel | averages and buckets that hide suffering | 09 — The Average Lie |
| pixel → human | alert fired, nobody paged | 05 — The Alert Nobody Saw |
| all of it | who watches the watcher? | 06 — The Dead Man's Switch |

This table is the arc's trailer — end the episode on it.

## 12. Metrics: The Episode Dashboard

Dashboard "Episode OBS-01 — The Life of a Metric" (uid `obs01-life`), four
panels — the chain, watchable:

| Panel | Query | What it shows |
|---|---|---|
| The Data Point | `node_memory_MemAvailable_bytes` | the series we follow, all links intact |
| Delivery Health | `up{job="node-exporter"}` + `scrape_duration_seconds{job="node-exporter"}` | link 3 working — and how hard |
| The Vault's Population | `prometheus_tsdb_head_series` | link 4's memory cost, live |
| The Pipeline Heartbeat | `rate(prometheus_tsdb_head_samples_appended_total[1m])` | samples/sec — the true cost of monitoring |

**Show it:** Panel 1 during Links 5-6; Panel 2 during Link 3; Panels 3-4
during Link 4. The full query set with explanations is in
`promql/queries.md`.

## 13. Cleanup

```bash
make cleanup-obs01
# -> "nothing to clean — this episode is read-only by design"
```

No workloads were deployed, no config changed. If you want to remove the
dashboard from Grafana, delete it in the UI (optional).

---

## Troubleshooting

**`curl :9100/metrics` times out** — node-exporter is a DaemonSet with
`hostNetwork: true`; it's reachable at the NODE's IP, not through a Service.
Confirm the pod is running on that node:
`kubectl get pods -n monitoring -l app=node-exporter -o wide` (check the
NODE column), and use that node's IP.

**`up{job="node-exporter"}` shows a 0** — check the targets page
(Status → Targets) for the error string; the most common lab cause is the
pod-discovery relabeling (the job keeps only pods labeled
`app: node-exporter` and reads the port from the `prometheus.io/port`
annotation — both are set in `lab/observability/node-exporter.yaml`).

**`prometheus_tsdb_head_*` queries return nothing** — the self-scrape job
(`job_name: prometheus → localhost:9090`) must be up; check
`up{job="prometheus"}`. If you edited `prometheus.yaml`, Prometheus needs a
restart to load it (`kubectl rollout restart deployment/prometheus -n
monitoring`) — it does not hot-reload ConfigMaps (see
`docs/TROUBLESHOOTING.md`).

**The kernel number and the exporter number don't match EXACTLY** — they
will differ slightly: `/proc/meminfo` is read by you and by the exporter at
different moments, and memory moves constantly. They should match in the
megabytes, not the bytes — that discrepancy (measurement moments) is
Episode 08's whole topic, foreshadowed.

**MemAvailable in `/proc` is in kB, the metric in bytes** — yes: the
exporter converts (×1024). Do the arithmetic on camera; it's a nice beat.
