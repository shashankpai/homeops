# The Life of a Metric — from the Linux Kernel to a Pixel
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for 8 phases (~16 minutes).
> **Style:** Foundations episode — the same descent DNA as Season 1, but we
> follow **a data point** instead of a corpse: from the graph you stare at,
> down to the kernel counter where the number was born.
> **The data point:** `node_memory_MemAvailable_bytes` — the same metric that
> caught the eviction in Season 1, running on the lab's real stack.

---

## Phase 1 — Hook: The Line That Settled an Argument (0:00 – 1:00)

[0:00]

This line right here — [gesture at a Grafana graph] — settled an argument last episode. Season 1, Episode 2: the node was melting down, and it was this line, `node_memory_MemAvailable_bytes`, falling toward the eviction threshold, that proved WHO killed those pods and WHEN.

[0:20]

And it hit me — most engineers stare at these lines all day, and have never once asked the question: where does this line actually COME from? Like, physically. What has to be true, in what order, for that pixel to be that color at that moment?

[0:40]

Because here's the thing: every number on your screen is evidence in a chain of custody with six links. A kernel counter, a translator, a delivery run, a vault, a question, and a pixel. Break any link and the line lies to you — or vanishes entirely.

[0:55]

Today we descend them all. Backwards — from the pixel you stare at, down to the kernel where the number was born. Let's go find the origin of a data point.

---

## Phase 2 — Link 6: The Pixel (1:00 – 3:00)

[1:00]

We start, like every investigation, at the surface — the dashboard. Grafana, the Episode 2 dashboard actually, and there's our line: node memory available, wobbling around its happy value.

[1:15 — show Grafana, zoom in]

Now I want to ruin graphs for you, just a little. Zoom in. Way in. That smooth line? It's a lie of smoothness. It's actually DOTS — sampled every fifteen seconds, and Grafana kindly draws connections between them.

[1:40]

Fifteen seconds. Between every pair of dots, fifteen seconds of reality is unobserved. In Season 1 we leaned on this on purpose — our leaky payment service allocated two megabytes every two seconds, slow enough that the climb showed up across multiple dots instead of dying invisibly between two of them.

[2:00]

So the pixel is an interpolation over samples. Next question: where do the samples come from? Grafana doesn't store anything — it's a painting layer. It asks a question, someone else answers. Link five.

---

## Phase 3 — Link 5: The Query (3:00 – 5:00)

[3:05]

The question is this — PromQL:

[3:10 — show Prometheus UI]

```promql
node_memory_MemAvailable_bytes
```

[3:20]

And switch the UI from graph view to TABLE view — because this is what a metric actually IS. A name... and labels. Look at the output: the metric name, then instance, job, and a value. That combination — name plus label values — is a single time series. One unique stream of dots. The name is WHAT we're measuring; the labels are the dimensions: which machine, which job scraped it.

[3:50]

One metric family can be thousands of series. Add a label with ten values, you get ten series per existing one. Multiply that by an unbounded label and... well. That's a future episode's apocalypse. For now: hold the mental model — a series is name plus labels, identified by its full label set.

[4:20]

The query engine behind this is Prometheus itself — it doesn't just collect, it indexes every series by label, so questions like "this metric, that machine" are instant lookups.

[4:40]

So: a query found the series. But where are the DOTS stored? Link four — the vault.

---

## Phase 4 — Link 4: The Vault (5:00 – 7:00)

[5:00]

Prometheus is its own database — the Time Series DataBase, TSDB. And here's a delicious recursion: Prometheus monitors itself. It scrapes its own /metrics endpoint — we configured that in the lab, job name "prometheus" — which means we can query the vault ABOUT the vault.

[5:20 — show Prometheus UI]

```promql
prometheus_tsdb_head_series
```

[5:30]

The number of series currently in memory, in the "head block" — the hot, recent data being appended to right now. Watch it, it's basically flat for us — a small lab, thousands of series. Production clusters: millions. And memory usage tracks series count almost linearly — which is exactly the lever we'll pull in the cardinality episode.

[5:55]

Samples flow into the head block, get compressed into chunks, and periodically flush to disk — on the lab, a persistent volume. Query anything older than a few hours and you're reading from disk; anything recent, from memory.

[6:15]

```promql
rate(prometheus_tsdb_head_samples_appended_total[1m])
```

[6:25]

The ingestion rate — samples per second arriving into the vault. This is the pipeline's heartbeat, and a number you want on your wall: it's the true cost of your monitoring, in data points per second.

[6:50]

So the vault holds the dots. But it doesn't go GET anything — the vault waits at home. Somebody does a delivery run. Link three.

---

## Phase 5 — Link 3: The Delivery Run — the Scrape (7:00 – 9:30)

[7:00]

This is Prometheus's most controversial design decision, and it's worth internalizing: **pull, not push**. Prometheus doesn't wait for metrics to be sent to it. It goes and GETS them — a scrape — every fifteen seconds, from every target.

[7:20 — show Prometheus UI, Status → Targets]

The targets page: every series of deliveries. There's node-exporter, one per node — three targets. kube-state-metrics. The kubelets, cAdvisor, Prometheus itself. Each row: the endpoint, the scrape interval, the LAST scrape, and how long it took.

[7:45]

And the vault knows its own delivery health — two metrics every observability stack should show you on a wall:

[7:55]

```promql
up{job="node-exporter"}
```

[8:05]

`up` is 1 when the last scrape succeeded, 0 when it failed. It's not a metric anyone EXPORTS — Prometheus writes it itself, per scrape, like a delivery driver signing the log.

[8:20]

```promql
scrape_duration_seconds{job="node-exporter"}
```

[8:28]

And how long each delivery took. Watch this number — normally well under a second. When a target gets too heavy — too many series to serialize in fifteen seconds — this number climbs toward the interval, scrapes start failing, and the graph... develops holes. Future episode. For now, taste the foreshadowing.

[8:55]

Where does the target list come from? On the lab — service discovery. Look at the scrape config: Prometheus queries the Kubernetes API, finds pods labeled node-exporter, and for each one rewrites the address to pod IP, port nine-thousand-one-hundred — that's the relabeling magic in our prometheus.yml. A new node comes up, the DaemonSet plants an exporter on it, and it appears in targets — no config change. THAT's how the lab's stack self-assembles.

[9:20]

So: a delivery run, every fifteen seconds, from an address. What's AT the address? Link two.

---

## Phase 6 — Link 2: The Translator — the Exposition (9:30 – 11:45)

[9:30]

Let's skip the middleman and go straight to the source. node-exporter runs with hostNetwork — so its port is the node's port. From my workstation:

[9:42 — show terminal]

```bash
curl -s http://192.168.1.82:9100/metrics | head -20
```

[9:55]

And there it is — the exposition format. Metrics as plain text. A HELP line explaining what it is, a TYPE line, and then the actual series: name, labels, value. Thousands of lines of this, one endpoint, no authentication on our lab.

[10:20 — show terminal]

Let's find OUR data point:

```bash
curl -s http://192.168.1.82:9100/metrics | grep -A2 MemAvailable
```

[10:35]

```
# HELP node_memory_MemAvailable_bytes Memory information field MemAvailable.
# TYPE node_memory_MemAvailable_bytes gauge
node_memory_MemAvailable_bytes 1.992323072e+09
```

[10:50]

One point nine nine two three... times ten to the ninth. About 1.99 gigabytes available. THE number. Well — almost. A gauge, snapshotted at the moment of scrape. The exposition is a translator: it doesn't remember anything, it just renders the current truth as text, on demand. Scrape it a second later, get a slightly different number. The TIME DIMENSION isn't in the exporter at all — the vault builds the history by sampling this endpoint every fifteen seconds.

[11:25]

So where does the TRANSLATOR get its numbers? It doesn't invent them. Link one — the origin.

---

## Phase 7 — Link 1: The Origin — the Kernel (11:45 – 13:30)

[11:45]

node-exporter mounts the host's /proc filesystem — /host/proc inside the container — and reads the kernel's own accounting files. SSH to the node and read the SAME file the exporter reads:

[12:00 — show terminal]

```bash
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.82
grep MemAvailable /proc/meminfo
```

[12:12]

```
MemAvailable:    1945588 kB
```

[12:25]

One million, nine hundred forty-five thousand... kilobytes. Multiply by 1024: one point nine nine two gigabytes — the SAME number the exporter served, the same number in the vault, the same number in the graph. /proc is the kernel's API — MemAvailable is the kernel's own estimate of how much memory it could give out without swapping, computed from live page accounting.

[12:55]

And notice what the translator did: the kernel speaks kilobytes, Prometheus speaks bytes. The chain even does unit conversion — a tiny detail, but it's why metric hygiene matters: every link assumes the one before it was honest.

[13:15]

So there's our data point's origin: a kernel counter, born in /proc, translated to text, delivered by scrape, stored as a series, found by a query, painted as a pixel. Six links, one number, three honest witnesses of itself along the way. Every metric you have ever graphed — every single one — took this exact journey.

---

## Phase 8 — The Full Chain, and Every Way It Breaks (13:30 – 16:00)

[13:30]

Let's walk the chain forward — the direction the data actually flows:

[13:38 — show diagram]

```
kernel counter → exporter → scrape (15s) → TSDB → query → pixel
   /proc        translation   delivery run    vault    lookup   painting
```

[13:55]

And here is the whole rest of this series, in one table. Every link has a failure mode, and each one is an upcoming episode:

[14:00 — show table]

| Link | How it breaks | The episode |
|---|---|---|
| exporter → scrape | too many series to serialize — scrape timeouts, `context deadline exceeded` | 04 — Cardinality Explosion |
| TSDB | too many series to store — Prometheus OOMKilled by its own limit | 04 — Cardinality Explosion |
| scrape → vault | target down, samples stop, graph goes... flat? | 07 — Why Your Graph Has Holes |
| the observers | four sources, one pod, three different numbers | 08 — Three Numbers, One Pod |
| query → pixel | averages and buckets that hide the users who suffer | 09 — The Average Lie |
| pixel → human | the alert fired, nobody was paged | 05 — The Alert Nobody Saw |
| all of it | who watches the watcher? | 06 — The Dead Man's Switch |

[14:50]

The foundations are laid: you now know the machine. The rest of the arc is every way the machine betrays you — and how to make each link honest again.

[15:05]

If you're new here: this stack — Prometheus, Grafana, node-exporter, kube-state-metrics — is running on a three-node K3s cluster, and everything you just watched me do is in the repo. One command per episode reproduces all of it.

[15:25]

Next episode: the four observers. node-exporter, cAdvisor, kube-state-metrics, and the app itself are ALL watching your cluster right now — and they disagree about what they see. Knowing who measures what is the difference between debugging and guessing.

[15:50]

Go follow one of your own metrics to its origin. It's a surprisingly satisfying walk. Subscribe — we go under the monitor next.
