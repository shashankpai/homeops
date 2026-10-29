# The Life of a Metric — from the Linux Kernel to a Pixel
## YouTube Metadata

---

## Title Options

### Primary (recommended)

**How Prometheus Works: The Life of a Metric (From Linux Kernel to Pixel)**

### Alternatives

1. **Where Does a Grafana Graph Actually Come From? (6 Links, 1 Data Point)**
   - Question-first — the exact curiosity the episode creates.

2. **Prometheus Architecture Explained by Tracing ONE Metric (Live)**
   - Search-heavy: "prometheus architecture" is a top query in this space.

3. **What Is a Time Series, Really? A Metric's Journey from /proc to Pixel**
   - Targets the concept gap (series = name + labels) with the journey hook.

4. **Pull vs Push, Scrapes, and the TSDB — How Monitoring Really Works**
   - Keyword-dense: pull model, scrape interval, TSDB — all high-search terms.

5. **The Chain of Custody Behind Every Number on Your Dashboard**
   - The evidence framing — ties to the series' detective DNA.

### SEO Notes

- Primary keywords: `prometheus architecture`, `how prometheus works`,
  `prometheus scrape`, `what is a time series`, `node-exporter`
- Secondary: `grafana data source`, `prometheus tsdb`, `exposition format`,
  `pull vs push metrics`, `scrape interval`
- Foundations episodes are the arc's **top-of-funnel**: these queries
  vastly out-search the incident topics — this episode is the growth engine.

---

## Thumbnail Concept

### Primary Design

**Layout:** a horizontal chain (the series' ladder visual):

- Left: a glowing Grafana line-graph fragment (the pixel)
- Right: a terminal fragment showing `MemAvailable: 1945588 kB` (the kernel)
- Between them: 4 small connected nodes (query · vault · scrape · exporter),
  dimmed, with a red arrow running pixel → kernel (the descent direction)
- Top text, bold yellow: **"WHERE DOES THIS LINE COME FROM?"**

**Overall mood:** a detective board with string. The viewer should feel
the pull to trace it themselves.

### Alternative Concepts

**Concept B — The Dot Reveal:** a graph zoomed until it's visibly dots,
"IT'S DOTS. 15 SECONDS APART."

**Concept C — Three Forms, One Number:** `1.99e9` / `1945588 kB` / a graph
line, "=" between them, "ONE NUMBER, SIX LINKS".

---

## YouTube Description

```
How Prometheus Works: The Life of a Metric (From Linux Kernel to Pixel)

That line on your Grafana dashboard just settled an argument. But have you ever asked — where does it actually COME from? Physically? Every number on your screen is evidence in a chain of custody with six links: a kernel counter, a translator, a delivery run, a vault, a question, and a pixel.

In this episode we descend the whole chain — backwards — following one real metric (node_memory_MemAvailable_bytes, the same one that caught the eviction in our Kubernetes series) from the pixel you stare at down to /proc/meminfo where the number is born.

We cover:
• What a graph really is — the smooth line is a LIE: it's dots, 15 seconds apart, painted between
• What a time series actually IS — name + labels = one unique stream (the definition most people skip)
• The Prometheus TSDB — the vault: head series, chunks, and why memory tracks series count almost linearly
• Pull, not push — the scrape: why Prometheus goes and GETS metrics every 15 seconds, and how service discovery assembles the target list with zero config
• `up` and `scrape_duration_seconds` — the delivery receipt and the stopwatch (the two metrics every stack should have on a wall)
• The exposition format — metrics as plain text: curl a node-exporter directly and read what the scrape actually picks up
• The origin — /proc/meminfo, the kernel's own accounting, and the kB-to-bytes conversion every link assumes
• The failure map — how each link breaks, and which upcoming episode turns it into a war story (cardinality, graph holes, the average lie, and more)

Everything runs live on a 3-node K3s cluster with Prometheus, Grafana, node-exporter and kube-state-metrics — the same stack every episode of this series uses. Read-only episode: nothing deployed, nothing changed, one command reproduces it all.

⏱ Timestamps:
0:00  - The line that settled an argument
1:00  - Link 6: the pixel — the line is dots, 15s apart
3:00  - Link 5: the query — what a time series actually IS
5:00  - Link 4: the vault — TSDB, head series, the ingestion heartbeat
7:00  - Link 3: the delivery run — pull, scrapes, up, service discovery
9:30  - Link 2: the translator — curl the exposition format raw
11:45 - Link 1: the origin — /proc/meminfo and the kB→bytes arithmetic
13:30 - The full chain forward + the failure map (the series trailer)

🔗 New to observability? This is the arc's on-ramp — start here.
🔗 Coming next: The Four Observers — node-exporter vs cAdvisor vs kube-state-metrics vs the app itself
🔗 Season 1 (Kubernetes pod deaths, the full investigation series): see the channel

🛠 Lab: 3-node K3s on Proxmox, Prometheus + Grafana + node-exporter + kube-state-metrics. All configs in the repo — one command per episode reproduces everything.

If this was helpful, subscribe — the rest of the arc is every way this machine breaks and lies.

#Prometheus #Observability #Kubernetes #Grafana #SRE
```

### Short Description (Shorts / social)

```
That line on your dashboard? It's dots, 15 seconds apart, that traveled through SIX links of custody from the Linux kernel to your screen. We trace one metric all the way down — pixel to /proc. 🕵️

Full episode: [link]
#Prometheus #Observability #Kubernetes
```

---

## Hashtags

### Primary (YouTube description — first 3 show above the title)

```
#Prometheus #Observability #Kubernetes
```

### Full set (description end)

```
#Prometheus #Observability #Kubernetes #Grafana #SRE #DevOps #TimeSeries #NodeExporter #Monitoring #SiteReliabilityEngineering #PullVsPush #TSDB #LearnKubernetes #Metrics #PlatformEngineering
```

---

## Backend Metadata

### Category
Science & Technology → Software Tutorials

### Tags
```
prometheus, prometheus architecture, how prometheus works, prometheus scrape, what is a time series, node-exporter, grafana, tsdb, exposition format, pull vs push metrics, scrape interval, up metric, service discovery, kubernetes monitoring, observability, sre, devops, k3s, promql, monitoring explained
```

### Series
Kubernetes Under the Hood — Observability Arc, Episode 01 (Foundations)

### Estimated Duration
~16 minutes

### Captions/Subtitles
Full narration → .srt; auto-translate to Spanish, Portuguese, French, German, Hindi

---

*End of Metadata*
