# Observability Arc — The Monitor Under the Hood

> **A 9-episode sub-series inside Kubernetes Under the Hood.**
> Season 1 asked *who kills pods*. This arc asks how the **monitoring itself**
> works — and then, episode by episode, how it breaks, and how it lies.

**Format:** same series DNA — *incident → investigation → root cause → fix*,
with the one twist that in the foundations tier, we follow **a data point**
instead of a corpse.

**Two tiers:**

- **Foundations (Ep 01–03)** — the on-ramp: introduce the stack the series
  already runs on, and how to use it with intent. Also the standalone entry
  point for viewers who are new to observability entirely.
- **Incidents (Ep 04–09)** — the war stories. Each one lands on prepared
  soil: every incident pays off a specific foundation episode.

**Zero-to-minimal new infrastructure:** every episode runs on the existing
lab (Prometheus, Grafana, node-exporter, kube-state-metrics, cAdvisor). The
only additions across the whole arc: Alertmanager (built on camera in Ep 05)
and two small ConfigMap apps (the cardinality bomb in Ep 04, the histogram
emitter in Ep 09) — both following the payment-service pattern.

---

## The Lineup

### Foundations — the on-ramp

| Ep | Title | The hook | Duration | Status |
|----|-------|----------|----------|--------|
| 01 | **The Life of a Metric** | That line on the dashboard just settled an argument. Where does it *come from*? Six links of custody, from the Linux kernel to a pixel — we descend them all | ~16 min | In production |
| 02 | **The Four Observers** | Four agents watch this cluster: node-exporter, cAdvisor, kube-state-metrics, and the app itself. They overlap, they disagree. Knowing who measures what is the difference between debugging and guessing | ~15 min | Planned |
| 03 | **Monitoring With Intent** | You could alert on 10,000 things. You should alert on about six. Golden signals, USE/RED, and the minimum viable dashboard — built on this lab's actual alert | ~15 min | Planned |

### Incidents — the war stories

| Ep | Title | The hook | Duration | Status |
|----|-------|----------|----------|--------|
| 04 | **Cardinality Explosion** | 9am: dashboards dark, Prometheus restarting. A label with unbounded values multiplied the series count a thousand-fold — and the watcher got OOMKilled by its own limit | ~20 min | Planned |
| 05 | **The Alert Nobody Saw** | The alert was FIRING for 40 minutes. Nobody was paged — because there was no Alertmanager. We build the missing pipeline on camera | ~16 min | Planned |
| 06 | **The Dead Man's Switch** | A watchdog alert that must ALWAYS fire. The day it stops, your alerting is dead. Who monitors the monitor? | ~13 min | Planned |
| 07 | **Why Your Graph Has Holes** | The graph was flat exactly when the pod died. Was memory flat — or was nobody watching? Staleness, the 5-minute lookback, and "no data ≠ zero" | ~15 min | Planned |
| 08 | **Three Numbers, One Pod** | `kubectl top` says 200MB, Grafana 187MB, the app 240MB. Nobody's lying — everyone measures something different | ~14 min | Planned |
| 09 | **The Average Lie** | Average latency 50ms, p99: 4 seconds. Histograms, bucket boundaries, and the counter-reset spike that shows up at every deploy | ~16 min | Planned |

**Arc total: ~140 minutes across 9 episodes.**

---

## The Payoff Map (foundation → incident)

Every foundation episode foreshadows specific incidents — the arc reads as
one continuous argument: *here's the machine (01–03), here's every way it
breaks and every way it lies (04–09)*.

| Foundation | Pays off in |
|---|---|
| 01 The Life of a Metric | 04 (where the pipeline multiplies series), 07 (where the pipeline breaks), 09 (what the pipeline can't average) |
| 02 The Four Observers | 08 (the observers disagree, on camera) |
| 03 Monitoring With Intent | 05 (the pipeline completes), 06 (alerting philosophy, weaponized) |

---

## Backlog / Fold-in Notes (nothing lost, arc kept tight)

Topics deliberately **not** standalone episodes, and where they live instead:

| Topic | Disposition |
|---|---|
| Scrape timeouts under series load | Fold into **04** (cardinality's final symptom: `context deadline exceeded`) |
| Alert fatigue (`for:` too short/long, inhibition, silences) | Fold into **05** and **06** segments |
| Dashboard lying (`$__rate_interval`, step aliasing) | Fold into **07** and **09** segments |
| **Retention Full: The Day History Vanished** (TSDB disk) | Backlog — candidate Ep 10 if the arc extends |
| **The Restart Ate the Evidence** (head block / WAL loss) | Backlog — candidate Ep 11; pairs with 04 |
| **PromQL Joins & Label Design** (`on(container) group_left`) | Backlog — craft episode, pairs with 03 |
| **Recording Rules & The 30-Second Dashboard** | Backlog — craft episode, pairs with 04 |

---

## Episode Template

Every episode follows the Season 1 artifact package (see
`episodes/03-diagnosing-oomkilled/` for the reference implementation):

```
episodes/observability/NN-title/
├── README.md               # episode overview + status + quick links
├── narration.md            # timestamped verbatim narration (phases)
├── storyboard.md            # visual sequences + production notes
├── lab-guide.md            # the manual: guided vs manual, sections,
│                           # per-panel metrics, troubleshooting
├── demo-flow-mapping.md     # narration phase → lab-guide section → script step
├── metadata.md             # SEO titles, thumbnail, description, hashtags
├── manifests/              # only when the episode needs one
├── promql/queries.md       # the episode's query set
├── dashboards/*.json       # the episode's Grafana dashboard
└── scripts/demo.sh + cleanup.sh   # the runnable backbone
```

Make targets: `make demo-obsNN` / `make cleanup-obsNN`.

---

*Arc opened 2026-10-29 with Episode 01 — The Life of a Metric.*
