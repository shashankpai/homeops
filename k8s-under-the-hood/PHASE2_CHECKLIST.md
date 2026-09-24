# Phase 2 Implementation Checklist

## Overview

Phase 2 will implement the observability stack, demo workload, and Episode 1 complete demo.

This checklist tracks the implementation of Steps 4-13 from the plan.

---

## Step 4: Observability Stack Manifests

### Prometheus
- [ ] Create `lab/observability/namespace.yaml`
  - [ ] monitoring namespace
  - [ ] RBAC: ServiceAccount, ClusterRole, ClusterRoleBinding
  
- [ ] Create `lab/observability/prometheus.yaml`
  - [ ] ConfigMap with prometheus.yml
  - [ ] Scrape configs: kubelet (/metrics, /metrics/cadvisor), kube-state-metrics, node-exporter, prometheus self
  - [ ] RBAC for accessing metrics endpoints
  - [ ] PVC: 5Gi (local-path-provisioner)
  - [ ] Deployment with retention: 7d, scrape_interval: 15s
  - [ ] Service (ClusterIP)

### Grafana
- [ ] Create `lab/observability/grafana.yaml`
  - [ ] ConfigMap: datasources.yaml (Prometheus)
  - [ ] ConfigMap: dashboards.yaml (provider config)
  - [ ] ConfigMap: oom-investigation.json (Episode 1 dashboard)
  - [ ] PVC: 2Gi
  - [ ] Deployment with admin/admin credentials
  - [ ] Service (ClusterIP)

### node-exporter
- [ ] Create `lab/observability/node-exporter.yaml`
  - [ ] DaemonSet (runs on every node)
  - [ ] hostNetwork: true, hostPID: true
  - [ ] Mounts: /proc, /sys, /
  - [ ] Service for Prometheus scraping

### kube-state-metrics
- [ ] Create `lab/observability/kube-state-metrics.yaml`
  - [ ] ServiceAccount, ClusterRole, ClusterRoleBinding
  - [ ] Deployment
  - [ ] Service for Prometheus scraping

### Verification
- [ ] All pods running in monitoring namespace
- [ ] Prometheus targets all UP
- [ ] Key metrics available:
  - [ ] container_memory_working_set_bytes
  - [ ] container_spec_memory_limit_bytes
  - [ ] kube_pod_container_status_restarts_total
  - [ ] kube_pod_container_status_last_terminated_reason
  - [ ] node_memory_MemAvailable_bytes
- [ ] Grafana accessible via port-forward
- [ ] Dashboard loads with data

---

## Step 5: Verify Observability Stack

- [ ] Update `lab/scripts/verify.sh` to check observability components
- [ ] Test Prometheus scraping
- [ ] Test Grafana dashboard loading
- [ ] Test metric queries

---

## Step 6: Demo Workload Manifests

### ShopNow Payment Service (Custom App)

#### Option A: Custom Flask App (Recommended)
- [ ] Create `episodes/01-oom-killed/app/app.py`
  - [ ] Flask app with endpoints:
    - [ ] /health — liveness probe
    - [ ] /allocate?mb=N — allocate N MB of memory
    - [ ] /status — show current memory usage
    - [ ] /metrics — Prometheus metrics (optional)
  - [ ] Memory allocation holds for configurable time
  - [ ] Graceful shutdown

- [ ] Create `episodes/01-oom-killed/app/Dockerfile`
  - [ ] Multi-stage build
  - [ ] Python 3.11 slim base
  - [ ] Install Flask, requests
  - [ ] Expose port 5000

- [ ] Build and push image
  - [ ] Build: `docker build -t shopnow-payment:latest .`
  - [ ] Push to local registry or load to K3s nodes

#### Option B: stress-ng (Simpler, for first pass)
- [ ] Use existing `polinux/stress-ng` image
- [ ] No custom build needed

### Manifests

- [ ] Create `episodes/01-oom-killed/manifests/payment-service.yaml`
  - [ ] Deployment: shopnow-payment:latest
  - [ ] Replicas: 1
  - [ ] Resources: request 128Mi, limit 256Mi
  - [ ] Liveness probe: /health
  - [ ] Readiness probe: /status
  - [ ] Service: ClusterIP, port 5000

- [ ] Create `episodes/01-oom-killed/manifests/payment-service-oom.yaml`
  - [ ] Same as baseline
  - [ ] Resources: request 128Mi, limit 256Mi (tight limit)
  - [ ] Annotation or label: "demo=oom"

- [ ] Create `episodes/01-oom-killed/manifests/payment-service-fixed.yaml`
  - [ ] Resources: request 256Mi, limit 512Mi (right-sized)
  - [ ] Add memory leak detection (app-level)
  - [ ] Add alerting rule (optional)

---

## Step 7: Failure Injection

- [ ] Create `episodes/01-oom-killed/scripts/trigger-oom.sh`
  - [ ] Deploy payment-service-oom.yaml
  - [ ] Wait for pod to be Running
  - [ ] Establish baseline: kubectl top pod, Grafana screenshot
  - [ ] Trigger memory allocation:
    - [ ] Option A: curl http://<pod-ip>:5000/allocate?mb=300
    - [ ] Option B: kubectl exec stress-ng --vm 1 --vm-bytes 300M
  - [ ] Observe: pod gets OOMKilled
  - [ ] Capture: kubectl describe pod, kubectl get events
  - [ ] Show exit code 137

---

## Step 8: Investigation Workflow

- [ ] Create `episodes/01-oom-killed/scripts/investigate.sh`
  - [ ] Layer 1: Kubernetes API
    - [ ] kubectl get pods
    - [ ] kubectl describe pod
    - [ ] kubectl get events
  - [ ] Layer 2: Container Runtime
    - [ ] SSH to worker node
    - [ ] sudo crictl ps -a
    - [ ] sudo crictl inspect <container-id>
    - [ ] Extract exit code 137
  - [ ] Layer 3: cgroup
    - [ ] Detect cgroup v1 vs v2
    - [ ] Read memory.current and memory.max (v2)
    - [ ] Or memory.usage_in_bytes and memory.limit_in_bytes (v1)
  - [ ] Layer 4: Linux Kernel
    - [ ] sudo journalctl -k | grep -i oom
    - [ ] sudo dmesg | grep -i "killed process"
  - [ ] Layer 5: Prometheus Metrics
    - [ ] Query container_memory_working_set_bytes
    - [ ] Query container_spec_memory_limit_bytes
    - [ ] Query kube_pod_container_status_restarts_total
    - [ ] Query kube_pod_container_status_last_terminated_reason

---

## Step 9: PromQL Queries

- [ ] Create `episodes/01-oom-killed/promql/queries.md`
  - [ ] 8 documented queries:
    1. [ ] Container memory usage vs limit (ratio)
    2. [ ] Container memory absolute usage
    3. [ ] Container memory limit
    4. [ ] Pod restart count
    5. [ ] Last terminated reason (OOMKilled)
    6. [ ] Node memory pressure
    7. [ ] Node memory available (absolute)
    8. [ ] Container OOM events
  - [ ] Each query documented with:
    - [ ] What it selects
    - [ ] Why it's useful
    - [ ] What the labels mean
    - [ ] How to modify it

---

## Step 10: Grafana Dashboard

- [ ] Create `episodes/01-oom-killed/dashboards/oom-investigation.json`
  - [ ] 7 panels:
    1. [ ] Pod Status (restart count) — Stat
    2. [ ] Last Termination (OOMKilled reason) — Stat
    3. [ ] Memory Usage (working set over time) — Time series
    4. [ ] Memory Limit (ceiling) — Time series (dashed)
    5. [ ] Usage vs Limit (ratio 0-100%) — Gauge
    6. [ ] Node Memory (available) — Time series
    7. [ ] OOM Events (kernel count) — Stat/Counter
  - [ ] Dashboard answers: WHAT, WHEN, WHERE, HOW SEVERE, WHY, WHAT NEXT
  - [ ] Integrate into Grafana ConfigMap

---

## Step 11: Fix and Verification

- [ ] Document fix procedure in `episodes/01-oom-killed/README.md`
  - [ ] Right-size resources (not just "increase limit")
  - [ ] Analyze actual memory usage from Grafana
  - [ ] Set request = actual + headroom
  - [ ] Set limit = request + spike headroom
  - [ ] Add memory leak detection (app-level)
  - [ ] Add alerting rule (optional)

- [ ] Verification procedure
  - [ ] kubectl apply -f payment-service-fixed.yaml
  - [ ] Wait 5 minutes
  - [ ] kubectl get pods — 0 restarts
  - [ ] Trigger same load — no OOM
  - [ ] Grafana shows memory under limit

---

## Step 12: Cleanup Scripts

- [ ] Create `episodes/01-oom-killed/scripts/cleanup.sh`
  - [ ] kubectl delete -f manifests/payment-service-oom.yaml
  - [ ] kubectl delete -f manifests/payment-service.yaml
  - [ ] Keep observability stack running
  - [ ] Ready for next episode

- [ ] Create `episodes/01-oom-killed/scripts/demo.sh`
  - [ ] Orchestrates the full demo:
    1. [ ] Deploy baseline (payment-service.yaml)
    2. [ ] Show healthy state
    3. [ ] Deploy OOM variant (payment-service-oom.yaml)
    4. [ ] Trigger OOM
    5. [ ] Show OOMKilled status
    6. [ ] Run investigation workflow
    7. [ ] Show Grafana dashboard
    8. [ ] Deploy fixed variant
    9. [ ] Verify no OOM
    10. [ ] Cleanup

---

## Step 13: Content Production

### Short-Form Script (60-90 seconds)

- [ ] Create `episodes/01-oom-killed/content/short-form-script.md`
  - [ ] 0:00 Hook: "Your Pod says OOMKilled. But Kubernetes didn't actually kill it."
  - [ ] 0:05 Problem: Show OOMKilled pod, restart loop
  - [ ] 0:15 Demo: Trigger memory allocation
  - [ ] 0:30 Under the hood: cgroup → kernel → SIGKILL
  - [ ] 0:45 Observability: Grafana shows memory hitting limit
  - [ ] 1:00 Fix: Right-size the pod
  - [ ] 1:10 Takeaway: OOMKill is Linux, not Kubernetes

### Long-Form Outline (8-15 minutes)

- [ ] Create `episodes/01-oom-killed/content/long-form-outline.md`
  - [ ] 1. Introduction (30s)
  - [ ] 2. Prerequisites (30s)
  - [ ] 3. Architecture (1m)
  - [ ] 4. Lab setup (1m)
  - [ ] 5. Baseline (30s)
  - [ ] 6. Failure injection (1m)
  - [ ] 7. Under the hood (2m)
  - [ ] 8. Observability (1.5m)
  - [ ] 9. Investigation (1.5m)
  - [ ] 10. Root cause (30s)
  - [ ] 11. Fix (1m)
  - [ ] 12. Verification (30s)
  - [ ] 13. Production lessons (1m)

### Shot List

- [ ] Create `episodes/01-oom-killed/content/shot-list.md`
  - [ ] SHOT 1: Terminal — kubectl get pods (OOMKilled)
  - [ ] SHOT 2: Grafana — memory graph hitting limit
  - [ ] SHOT 3: Terminal — kubectl describe pod
  - [ ] SHOT 4: SSH to worker — crictl inspect (exit code 137)
  - [ ] SHOT 5: SSH to worker — cgroup memory files
  - [ ] SHOT 6: SSH to worker — journalctl -k (OOM)
  - [ ] SHOT 7: Architecture diagram
  - [ ] SHOT 8: Terminal — fix applied (0 restarts)
  - [ ] SHOT 9: Grafana — memory stable under new limit

### Episode README

- [ ] Create `episodes/01-oom-killed/README.md`
  - [ ] Episode objective
  - [ ] Architecture diagram
  - [ ] Lab prerequisites
  - [ ] Lab setup guide
  - [ ] Demo flow
  - [ ] Investigation workflow
  - [ ] Root cause explanation
  - [ ] Fix procedure
  - [ ] Verification steps
  - [ ] Cleanup
  - [ ] Production lessons
  - [ ] References

### Troubleshooting

- [ ] Create `episodes/01-oom-killed/troubleshooting.md`
  - [ ] Common issues and solutions
  - [ ] How to debug each layer
  - [ ] How to reset the demo

---

## Final Verification

- [ ] All manifests deploy without errors
- [ ] All scripts are executable and work correctly
- [ ] All documentation is complete and accurate
- [ ] Demo can be run end-to-end without manual intervention
- [ ] Investigation workflow covers all 5 layers
- [ ] Grafana dashboard displays all metrics correctly
- [ ] Content scripts are ready for recording

---

## Success Criteria

✅ Phase 2 is complete when:

1. Lab can be provisioned with `make setup`
2. Observability stack is fully deployed and operational
3. Demo workload can be deployed and triggered
4. OOMKill can be reliably reproduced
5. Investigation workflow covers all 5 layers
6. Grafana dashboard shows the OOM event clearly
7. Fix procedure is documented and verified
8. Content scripts are ready for YouTube recording
9. All code is documented and reproducible
10. Cleanup leaves the lab ready for the next episode

---

## Timeline Estimate

- Observability manifests: 2-3 hours
- Demo workload: 1-2 hours
- Scripts: 2-3 hours
- PromQL queries: 1 hour
- Grafana dashboard: 1-2 hours
- Content production: 2-3 hours
- Testing and refinement: 2-3 hours

**Total: ~14-20 hours**

---

## Notes

- Use existing manifests from `kairos-test/k8s/` as templates
- Adapt Prometheus scrape configs to include cAdvisor
- Test all scripts on the actual lab before finalizing
- Verify metric names against actual Prometheus instance
- Ensure cgroup v1/v2 auto-detection in investigation scripts
- Keep observability stack reusable for future episodes
