# Observability Ep 01: Demo Flow Mapping
## Narration Phase → Lab-Guide Section → Script Step

| Narration Phase | Time | Lab-Guide Section | Demo Script Step | Key Artifacts |
|---|---|---|---|---|
| 1 — Hook: the line that settled an argument | 0:00–1:00 | §1 Episode Overview | — (framing) | Season 1 Ep 2 dashboard (the drain line) |
| 2 — Link 6: The Pixel | 1:00–3:00 | §Link 6 (Grafana) | STEP 2 | `life-of-a-metric.json` Panel 1, zoom-in on the 15s dots |
| 3 — Link 5: The Query | 3:00–5:00 | §Link 5 (PromQL) | STEP 3 | Table view, `count(...)` — the series definition |
| 4 — Link 4: The Vault | 5:00–7:00 | §Link 4 (TSDB) | STEP 4 | `prometheus_tsdb_head_series`, ingestion rate |
| 5 — Link 3: The Scrape | 7:00–9:30 | §Link 3 (scrape) | STEP 5 | Targets page, `up`, `scrape_duration_seconds`, discovery config |
| 6 — Link 2: The Exposition | 9:30–11:45 | §Link 2 (exposition) | STEP 6 | `curl :9100/metrics`, the MemAvailable grep |
| 7 — Link 1: The Kernel | 11:45–13:30 | §Link 1 (kernel) | STEP 7 | ssh + `grep MemAvailable /proc/meminfo`, the kB→bytes math |
| 8 — The Full Chain + failure map | 13:30–16:00 | §11 Full Chain, §12 Dashboard | STEP 8 | The arc trailer table (matches arc README) |

## Key Demo Sections

### The descent (Phases 2–7 → STEPS 2–7)
The episode's spine — same descent DNA as Season 1, following a data point
instead of a corpse. Notes:
- Each link ENDS with a one-line bridge to the next ("where do the samples
  come from?" / "what's AT the address?") — never lose the thread
- The Prometheus UI work (Links 5, 4, 3) is tab-flipping: query view →
  table view → Status→Targets. Rehearse the tab order once
- The exposition curl (Link 2) and the ssh (Link 1) land the biggest payoff:
  the SAME number appearing in all three forms (e, bytes, kB) — do the ×1024
  arithmetic on camera

### The arc trailer (Phase 8 → STEP 8)
The failure-map table IS the arc's trailer — every row names a future
episode. Record it full-frame; it's also the natural shorts cut.

## Notes for Video Production

- Record the Grafana zoom (Phase 2) slowly — the dot-reveal is the
  foundations-tier "aha" and deserves 3-4 seconds of silence
- Have three terminals pre-positioned: (1) curl, (2) Prometheus UI,
  (3) ssh — the descent moves fast once it starts
- The self-referential beat (querying the vault about the vault) is the
  episode's cleverest moment — don't rush `prometheus_tsdb_head_series`
- Everything is read-only: zero re-take cost. If any step fumbles, re-run
  the step, not the episode
- Suggested shorts: (a) the 15-seconds-between-dots zoom, (b) the
  same-number-three-ways arithmetic, (c) the failure-map trailer

## Quick Reference: Where Each Artifact Is Used

| Artifact | Used In |
|---|---|
| `scripts/demo.sh` | The runnable backbone (STEPS 1–8) |
| `scripts/cleanup.sh` | No-op by design (uniform make pattern) |
| `lab-guide.md` | The manual, link-by-link path (recording) |
| `promql/queries.md` | Phases 3–5 (the chain's queries) |
| `dashboards/life-of-a-metric.json` | Phases 2, 4 (Panel 1: the data point; Panels 2–4: the chain's health) |
| `lab/observability/node-exporter.yaml` | Phase 5–6 (the discovery annotation, hostNetwork, /proc mount) |
| `lab/observability/prometheus.yaml` | Phase 5 (the scrape job + relabel_configs) |
