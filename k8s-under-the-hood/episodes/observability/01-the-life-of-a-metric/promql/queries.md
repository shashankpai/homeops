# Observability Ep 01 — PromQL Queries: The Life of a Metric

The chain's queries, link by link. All against the lab's Prometheus
(http://192.168.1.81:30900 — any node IP).

---

## Link 6/5 — The series itself

### 1. The data point we follow

```promql
node_memory_MemAvailable_bytes
```

The star of the episode: the node's available memory, as node-exporter
samples it every 15s. In Prometheus's **Table** view this reveals what a
metric IS: name + label set + one value per series.

### 2. How many series in this one family?

```promql
count(node_memory_MemAvailable_bytes)
```

One per node (three). One metric family, many series — the multiplication
rule that explodes in Episode 04 when labels gain unbounded values.

## Link 4 — The vault, about the vault

Prometheus scrapes itself (job `prometheus` → `localhost:9090`), so the
database can be interrogated like any target:

### 3. Series in the hot head block

```promql
prometheus_tsdb_head_series
```

The number of unique time series currently memory-resident. Small lab:
thousands. Production: millions. **Memory tracks this number almost
linearly** — the single most important Prometheus metric, and the lever
Episode 04 pulls.

### 4. Chunks in the head block

```promql
prometheus_tsdb_head_chunks
```

Compressed runs of samples. Chunks:series above ~1 is normal (most series
have more than one chunk-window of recent data).

### 5. The pipeline's heartbeat — ingestion rate

```promql
rate(prometheus_tsdb_head_samples_appended_total[1m])
```

Samples per second flowing into the vault. This is monitoring's true cost,
in data points/second. Watch it while the lab idles, and again while an
episode demo runs — the delta is the demo's metric footprint.

### 6. Samples the last scrape actually delivered (per target)

```promql
scrape_samples_scraped{job="node-exporter"}
```

How many series one delivery run picks up from ONE node-exporter —
thousands from a single pod. Multiply by targets and interval, and you can
predict the ingestion rate by hand. (Good on-camera sanity math with #5.)

## Link 3 — Delivery health

### 7. The delivery receipt

```promql
up{job="node-exporter"}
```

`1` = last scrape succeeded, `0` = failed. Nobody exports this — Prometheus
writes it per scrape, per target. A whole monitoring philosophy in one
metric: the collector audits itself first.

### 8. The delivery duration

```promql
scrape_duration_seconds{job="node-exporter"}
```

Normally well under a second. When a target gets too heavy (too many series
to serialize inside the interval), this climbs toward 15s, then scrapes
start failing — the moment `up` flips to 0 and graphs develop holes
(Episode 07). Keep an eye on the p-max:

```promql
max(scrape_duration_seconds{job="node-exporter"})
```

## Link 2 — The translator, seen from the vault

### 9. How long the exposition takes to build

```promql
scrape_duration_seconds{job="kube-state-metrics"}
```

Same metric, different witness: KSM has to walk the API's state to render
its exposition — a heavier translation than node-exporter's file reads,
and it shows in the duration. Two translators, two costs.

## The chain, end to end (the episode's closing view)

### 10. All links at once

```promql
node_memory_MemAvailable_bytes
```
```promql
up{job="node-exporter"}
```
```promql
prometheus_tsdb_head_series
```
```promql
rate(prometheus_tsdb_head_samples_appended_total[1m])
```

Run all four side by side (the dashboard does): the series, the delivery
receipt, the vault's population, and the heartbeat. If all four are
healthy, every link of custody is intact — and any graph on your screen is
tellable the whole way down to `/proc`.

## Panel-to-story mapping (episode dashboard, uid `obs01-life`)

| Query | Chain link | Story beat |
|---|---|---|
| 1 | 6 → 1 | the data point, all links intact |
| 7, 8 | 3 | the delivery run — working, and how hard |
| 3 | 4 | the vault's population (memory's lever) |
| 5 | 4 | the heartbeat — monitoring's true cost |
| 6 | 3+4 | hand-checking the math (nice on-camera beat) |
| 9 | 2 | two translators, two costs |
