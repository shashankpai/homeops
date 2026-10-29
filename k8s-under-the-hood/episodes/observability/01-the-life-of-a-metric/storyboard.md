# The Life of a Metric — from the Linux Kernel to a Pixel
## Full Visual Storyboard

> **Duration:** ~16 minutes · **Format:** foundations descent — a data point
> traced backward through six links of custody
> **Principle:** same descent DNA as Season 1 (pixel → ... → kernel), but the
> "victim" is a number, and every link ends with a bridge question pulling
> the viewer to the next layer.

---

## Visual Style Guide

- Same conventions as the series (dark terminal 18pt+, trimmed output,
  red reserved for failure, diagrams white-on-dark)
- **New vocabulary for the foundations tier:** the chain diagram recurs —
  six links as a horizontal ladder, with the CURRENT link highlighted and
  all later links dimmed; each phase lights one more link as we descend
- The Prometheus UI gets the same respect as terminals: no browser chrome,
  zoomed to content

---

## Key Visual Sequences

### Sequence A — The Line That Settled an Argument (hook, 0:00–1:00)

- Cold open: the Season 1 Episode 2 drain graph (the eviction proof)
- "Where does this line COME from? Physically."
- Title card: THE LIFE OF A METRIC — six links of custody

### Sequence B — The Chain Ladder (recurring)

```
 6.pixel ─ 5.query ─ 4.vault ─ 3.scrape ─ 2.exposition ─ 1.kernel
   ▲
 (lit link moves left each phase; earlier links dim)
```

- Appears in the corner or on transitions; by Phase 7 all six are lit
- Final version (Phase 8) adds arrows flowing FORWARD: the data's direction

### Sequence C — The Dot Reveal (Link 6, 1:00–3:00)

- Grafana, slow zoom on the line... continuing to zoom... until the
  smoothness breaks into DOTS
- Annotation: "15 seconds of reality, unobserved, between every pair"
- Callback flash: payment-service's 2MB/2s pacing (one sentence + Season 1
  clip frame)

### Sequence D — The Series, Defined (Link 5, 3:00–5:00)

- Prometheus UI: Graph view → click **Table** — the reveal that a metric
  is name + labels + value
- Highlight the label set; "one family, many series" with the count query
- Foreshadow flash: "add a label with N values → N new series. (Episode 04
  turns this rule into an incident.)"

### Sequence E — The Vault, Interrogated (Link 4, 5:00–7:00)

- The recursion beat: querying Prometheus about Prometheus — hold on the
  self-scrape target row before running `prometheus_tsdb_head_series`
- Two numbers on screen: head series (big type) + ingestion rate
  ("monitoring's true cost, in data points per second")

### Sequence F — The Delivery Log (Link 3, 7:00–9:30)

- Status → Targets page: the full delivery map — every target, one screen
- `up` = the driver's signature; `scrape_duration_seconds` = the stopwatch
- YAML excerpt of the relabel_configs (2 lines, highlighted): the
  self-assembling target list

### Sequence G — Raw Text (Link 2, 9:30–11:45)

- Terminal: `curl :9100/metrics | head -20` — plain-text metrics, unvarnished
- Then the grep: HELP / TYPE / the series line — full screen, three lines
- "A stateless translator: it remembers NOTHING."

### Sequence H — The Origin + The Arithmetic (Link 1, 11:45–13:30)

- ssh → `grep MemAvailable /proc/meminfo` → `MemAvailable: 1945588 kB`
- **The money shot:** three numbers side by side —

```
exposition:  1.992323072e+09
/proc:       1945588 kB  ×1024  =  1.99 GB
pixel:       the line on the graph
```

- "Same number, three forms, six links. Every metric you've ever graphed
  took this exact journey."

### Sequence I — The Failure Map (arc trailer, 13:30–16:00)

- The chain, forward, with arrows — then the 7-row failure table
  (link → how it breaks → the episode), rows appearing as narrated
- Ends: "here's the machine (01–03). The rest of the arc is every way it
  breaks and every way it lies."
- This table doubles as the arc trailer AND a standalone short

---

## Section-by-Section Storyboard

| Phase | Time | Visuals | Action |
|---|---|---|---|
| 1 Hook | 0:00–1:00 | Seq A | Season 1 callback, the question |
| 2 Link 6 | 1:00–3:00 | Seq B + C | The dot reveal |
| 3 Link 5 | 3:00–5:00 | Seq D | Table view, series definition |
| 4 Link 4 | 5:00–7:00 | Seq E | The vault interrogated |
| 5 Link 3 | 7:00–9:30 | Seq F | Targets, up/duration, discovery |
| 6 Link 2 | 9:30–11:45 | Seq G | Raw exposition text |
| 7 Link 1 | 11:45–13:30 | Seq H | /proc + the arithmetic |
| 8 Chain + map | 13:30–16:00 | Seq I | Forward chain, failure map, outro |

---

## Production Notes

- **Everything is read-only** — zero re-take cost; fumble a step, re-run the
  step
- Pre-position three windows before recording: curl terminal, Prometheus
  UI, ssh terminal — the descent shouldn't wait on window management
- The dot reveal (Seq C) is the foundations-tier money shot: zoom slowly,
  let the dots appear, 3 seconds of silence
- The ×1024 arithmetic (Seq H) should be done honestly on screen (or a
  calculator app) — the moment the chain proves itself is the episode's
  trust anchor
- Thumbnail concept: the chain ladder with the pixel at one end and a
  glowing `/proc/meminfo` at the other, "WHERE DOES THIS LINE COME FROM?"
  across the top (see metadata.md)
