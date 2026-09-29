# Phase 3 Implementation Checklist — Episode 2

## Overview

Phase 3 implements Episode 2: **OOMKilled vs Evicted — They Are NOT the Same**.

A shorter comparison episode (~20 min, 11 narration phases) contrasting the two
memory-death actors: the Linux kernel (cgroup OOM killer, per-container) vs the
kubelet eviction manager (node-level, QoS-ranked). Includes a full live
observability demo mirroring Episode 1's Layer 5.

This checklist tracks the implementation of the episode's workload, failure
injection, investigation workflow, and content production.

Episode directory: `episodes/02-oomkilled-vs-evicted/`

---

## Step 1: Demo Workload Manifests

### Memory Hogs (BestEffort)

- [ ] Create `episodes/02-oomkilled-vs-evicted/manifests/memory-hog.yaml`
  - [ ] Namespace: `eviction-demo` (separate from `shopnow` so cleanup is isolated)
  - [ ] ConfigMap: `memory-hog-code` — stdlib-only Python app (same pattern as
        Episode 1's payment-service):
    - [ ] `GET /healthz` — liveness target (always 200)
    - [ ] `GET /usage` — current RSS in MB
    - [ ] `POST /allocate?mb=N` — gradual allocation (2MB/2s chunks) and hold
    - [ ] `POST /release` — drop held allocations
  - [ ] Deployment: `memory-hog`
    - [ ] 3 replicas
    - [ ] **NO `resources:` block at all — BestEffort QoS is the point**
    - [ ] `nodeSelector: kubernetes.io/hostname: __WORKER_NODE__` (placeholder —
          demo.sh substitutes the chosen worker's real node name)
    - [ ] python:3.12-slim, probes, hardened securityContext (same as Ep 1)
  - [ ] NO Service (pods are driven via `kubectl exec`, eviction doesn't need one)

### Contrast Victim (reuse Episode 1)

- [ ] demo.sh checks for `shopnow/payment-service`; deploys it from
      `episodes/01-oom-killed/manifests/payment-service.yaml` if missing
- [ ] Side-by-side: hog pods get `Evicted`, payment-service (Burstable,
      usage below request) survives — the QoS lesson

---

## Step 2: Failure Injection (Node Memory Pressure)

- [ ] Target node discovered dynamically:
      `kubectl get nodes -l node-role.kubernetes.io/agent` → first worker
- [ ] Eviction threshold (two options, lab-guide documents both):
  - [ ] **Option B (recommended):** raise the target worker's threshold to
        `memory.available<1Gi` via `/etc/rancher/k3s/config.yaml`
        (`kubelet-arg: ["eviction-hard=memory.available<1Gi"]`) +
        `systemctl restart k3s-agent` — safer for a 4GB worker AND teaches
        where thresholds live. Documented, reversible.
  - [ ] **Option A (fallback):** default `memory.available<100Mi` — needs ~3GB
        of hogs; riskier for lab stability
- [ ] demo.sh ramps in rounds: +256MB per hog per round, `kubectl top node`
      check after each round, stop at first eviction or max rounds
- [ ] Eviction detection: poll `kubectl get pods -n eviction-demo` for
      `STATUS: Failed / REASON: Evicted`; capture events
      ("The node was low on resource: memory")

---

## Step 3: Investigation Workflow

- [ ] Evicted pod view: `kubectl describe pod` —
      `Status: Failed, Reason: Evicted`, event
      `The node was low on resource: memory. Threshold quantity: ...`
- [ ] Node view: `kubectl describe node` — `MemoryPressure` condition,
      allocation of hogs, taints
- [ ] kubelet side (on the node, via ssh from controller):
  - [ ] `cat /etc/rancher/k3s/config.yaml` — the threshold config
  - [ ] `journalctl -u k3s-agent | grep -i evict` — kubelet's eviction log lines
        (vs Episode 1's `dmesg` kernel kills — two different logs, two authors)
- [ ] QoS ranking explanation: BestEffort → Burstable (usage-over-requests) →
      Guaranteed; PriorityClass tiebreak
- [ ] Side-by-side: re-trigger payment-service OOMKill and show both deaths
      in one session (the money shot)

---

## Step 4: PromQL Queries

- [ ] Create `episodes/02-oomkilled-vs-evicted/promql/queries.md` (~10 queries):
  - [ ] `node_memory_MemAvailable_bytes` — the drain
  - [ ] `kube_node_status_condition{condition="MemoryPressure"}` — condition flip
  - [ ] `kube_pod_status_reason{reason="Evicted"}` — the eviction event
  - [ ] `kube_pod_status_phase{phase="Failed"}` — pod gone from node
  - [ ] `container_memory_working_set_bytes{namespace="eviction-demo"}` — hog memory
  - [ ] Working set vs requests (usage-over-requests eviction ranking view)
  - [ ] Working set grouped by QoS class — who dies first and why
  - [ ] Contrast: `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`
  - [ ] Contrast: `kube_pod_container_status_restarts_total`
  - [ ] Node total working set vs MemAvailable

---

## Step 5: Grafana Dashboard

- [ ] Create `episodes/02-oomkilled-vs-evicted/dashboards/eviction-investigation.json`
      (same format/conventions as Episode 1's dashboard):
  - [ ] Panel 1: node memory available draining, eviction threshold as red
        dashed line (the mirror image of Ep 1's working-set climb)
  - [ ] Panel 2: `MemoryPressure` condition timeline (flips to true at eviction)
  - [ ] Panel 3: pod status reasons incl. `Evicted` events
  - [ ] Panel 4: QoS-lens working-set panel (hogs vs payment-service)
  - [ ] Panel 5: split-view row — Ep 1 sawtooth (container WS vs limit) next to
        Ep 2 node drain + eviction cliff
  - [ ] Refresh: 5s; tags: k8s-under-the-hood, episode-2, eviction

---

## Step 6: Orchestration Scripts

- [ ] Create `episodes/02-oom-killed/scripts/demo.sh` →
      `episodes/02-oomkilled-vs-evicted/scripts/demo.sh`
  - [ ] Same banner/pause guided-demo pattern as Episode 1
  - [ ] Steps: preflight (node discovery, payment-service check) → deploy hogs
        → baseline → ramp rounds → eviction watch → investigation → metrics
        pointers → side-by-side OOMKill re-trigger
  - [ ] Poll-based eviction detection (eviction timing is not deterministic —
        kubelet housekeeping interval)
  - [ ] Safety: max rounds cap; hint to run cleanup.sh if node destabilizes
- [ ] Create `episodes/02-oomkilled-vs-evicted/scripts/cleanup.sh`
  - [ ] Delete `eviction-demo` namespace
  - [ ] Verify `MemoryPressure` clears after hogs are gone
  - [ ] Leave payment-service + lab untouched

---

## Step 7: Content Production

### Narration (~11 phases, ~20 min)

- [ ] Create `episodes/02-oomkilled-vs-evicted/narration.md`
  - [ ] Verbatim timestamped narration, same style as Episode 1
  - [ ] Pattern per segment: SYMPTOM → OBSERVATION → HYPOTHESIS → COMMAND →
        EVIDENCE → ROOT CAUSE
  - [ ] Dedicated metrics phase (Phase 7) mirroring Ep 1's Layer 5 — the
        eviction watched live in Grafana

### Storyboard

- [ ] Create `storyboard.md`
  - [ ] Visual style guide (reuse Episode 1 conventions)
  - [ ] Key sequences: split-screen two victims; drain graph with threshold
        line; eviction cascade; comparison table full-frame

### Lab Guide

- [ ] Create `lab-guide.md` (~13 sections, mirrors Episode 1 structure)
  - [ ] Includes the eviction-threshold Option B step (documented, reversible)
        and its revert

### Demo Flow Mapping

- [ ] Create `demo-flow-mapping.md` — narration phase → lab-guide section

### Metadata

- [ ] Create `metadata.md`
  - [ ] Title options, thumbnail concepts (split `RESTARTS:3` vs `Evicted`),
        description with timestamps, hashtags, tags

---

## Step 8: Integration

- [ ] Makefile: `demo-ep02`, `cleanup-ep02` targets + help entries
- [ ] README.md: Episode 2 → In Progress
- [ ] Episode 3-4 skeleton READMEs (Season 1 completion outline)

---

## Final Verification

- [ ] `bash -n` passes on demo.sh / cleanup.sh
- [ ] `kubectl apply --dry-run=client` on memory-hog.yaml (needs lab)
- [ ] Dashboard JSON valid (`jq .`)
- [ ] `make -n demo-ep02` dry-run
- [ ] Full end-to-end run against the live lab BEFORE recording:
  - [ ] Eviction actually triggers (threshold crossed, hogs evicted)
  - [ ] payment-service survives round 1
  - [ ] Grafana panels show the drain + condition flip + eviction
  - [ ] Side-by-side OOMKill + Eviction captured

---

## Success Criteria

✅ Phase 3 is complete when:

- A viewer can run `make demo-ep02` on the lab and see a node-memory-pressure
  eviction happen live, with the QoS ranking demonstrated (hogs die,
  payment-service lives)
- The side-by-side contrast (OOMKilled vs Evicted) is visible in one session
  in both kubectl and Grafana
- All artifacts (narration, storyboard, lab-guide, dashboard, metadata) are
  ready for recording

---

## Timeline Estimate

- Manifests + scripts: 2-3 hours
- PromQL + dashboard: 1-2 hours
- Lab guide: 1-2 hours
- Narration + storyboard + metadata: 3-4 hours
- End-to-end verification: 1-2 hours

---

## Notes

- Node names are discovered dynamically (`kubectl get nodes`) — do NOT
  hardcode node names in scripts or docs
- Eviction timing is less deterministic than Episode 1's OOMKill — scripts
  poll, narration never promises exact timing
- The eviction-threshold change (Option B) must be a clearly documented,
  reversible lab-guide step — never a silent infra change
