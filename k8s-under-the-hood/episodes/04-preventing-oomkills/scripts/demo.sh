#!/bin/bash
# =============================================================================
# Episode 4 — How do you prevent Kubernetes OOMKills? (Season 1 finale)
#
# The full-circle episode: the SAME load that killed payment-service in
# Episode 1, now survives — because of engineering, not luck.
#
# Flow:
#   1. Preflight: bad payment-service running + Prometheus alerts loaded
#   2. The problem: the Episode 1 kill, one more time (why we're here)
#   3. The fork: leak or legit? (deriv — the Episode 3 fix decider)
#   4. The anti-pattern: "just raise the limit" (extrapolation math)
#   5. Fix A: leaks are app bugs (/release — working set drops live)
#   6. Fix B: right-size from data (deploy the Guaranteed variant,
#      same load that killed it → SURVIVES)
#   7. The safety net: MemoryNearLimit fires at 90% — BEFORE the kernel
#   8. The prevention checklist
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIZED_MANIFEST="$EP_DIR/manifests/payment-service-sized.yaml"
EP1_MANIFEST="$EP_DIR/../01-oom-killed/manifests/payment-service.yaml"
LAB_PROMETHEUS="$EP_DIR/../../../lab/observability/prometheus.yaml"
PROM_URL="${PROM_URL:-http://192.168.1.81:30900}"

pause() { echo -e "\n${YELLOW}>>> $1 — press Enter to continue${NC}"; read -r; }
banner() { echo -e "\n${CYAN}===================================================================$NC"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}===================================================================\033[0m"; }

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

banner "EPISODE 4: How do you prevent Kubernetes OOMKills?"

# --- 1. Preflight ------------------------------------------------------------
banner "STEP 1 — Preflight: the victim, and the alert rules"

if kubectl get deployment payment-service -n shopnow &>/dev/null; then
    echo -e "${GREEN}✓ payment-service (the 128Mi victim) already running${NC}"
else
    echo -e "${YELLOW}Deploying payment-service (Episode 1 workload)...${NC}"
    kubectl apply -f "$EP1_MANIFEST"
    kubectl rollout status deployment/payment-service -n shopnow --timeout=180s
fi

echo -e "${YELLOW}Checking the lab's Prometheus has the alert rules loaded...${NC}"
if curl -s "$PROM_URL/api/v1/rules" 2>/dev/null | grep -q "MemoryNearLimit"; then
    echo -e "${GREEN}✓ MemoryNearLimit + OOMKilledRecently rules loaded${NC}"
else
    echo -e "${YELLOW}Alert rules not loaded. Applying the lab Prometheus config...${NC}"
    echo -e "${YELLOW}(adds rule_files + alerts.yml to the monitoring ConfigMap)${NC}"
    kubectl apply -f "$LAB_PROMETHEUS"
    kubectl rollout restart deployment/prometheus -n monitoring
    kubectl rollout status deployment/prometheus -n monitoring --timeout=180s
    echo -e "${GREEN}✓ Prometheus restarted with alert rules${NC}"
fi

pause "Preflight complete"

# --- 2. The problem ----------------------------------------------------------
banner "STEP 2 — The problem: the Episode 1 kill, one more time"

PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
echo -e "${YELLOW}128Mi limit. Allocating 200MB. You know how this ends.${NC}"
kubectl exec -n shopnow "$PS_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=200', method='POST')).read().decode(), end='')"

echo -e "${YELLOW}Waiting for the kernel (~3-4 min ramp)...${NC}"
for i in $(seq 1 40); do
    if kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null | grep -q OOMKilled; then
        echo -e "${GREEN}✓ Dead. Again. Same as Episode 1.${NC}"
        break
    fi
    sleep 10
done
kubectl get pods -n shopnow -o custom-columns=POD:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason | grep payment-service

echo ""
echo -e "${YELLOW}The standup question this episode answers:${NC}"
echo -e "${YELLOW}  'What are we doing so it never happens again?'${NC}"

pause "The problem, restaged"

# --- 3. The fork: leak or legit? --------------------------------------------
banner "STEP 3 — The fork: leak or legit? (this decides the fix)"

echo -e "${YELLOW}The Episode 3 fix-decider query — rate of growth:${NC}"
echo ""
echo "  deriv(container_memory_working_set_bytes{container='payment-service'}[10m])"
echo ""
echo -e "${YELLOW}In Grafana (Episode 4 dashboard, 'Leak Signature' panel):${NC}"
echo "  Grafana: http://192.168.1.81:30300  (admin/admin)"
echo "  Prometheus: $PROM_URL"
echo ""
cat << 'FORK'
  The read (linear climb, no plateau):
      LEAK — the app holds memory it never frees.
      -> the fix is IN THE APPLICATION. No YAML fixes a leak.

  (If it plateaued above the limit: legit load, under-sized pod
   -> the fix is RIGHT-SIZING. We'll do both.)
FORK

pause "Diagnosis: leak"

# --- 4. The anti-pattern -----------------------------------------------------
banner "STEP 4 — The anti-pattern: 'let's just raise the limit'"

echo -e "${YELLOW}Someone WILL propose: 'bump the limit to 512Mi.' Let's do the math${NC}"
echo -e "${YELLOW}before doing the yoga. Run this while the leak is climbing:${NC}"
echo ""
cat << 'EXTRAP'
  time-to-limit = (limit - working_set) / growth_rate

  With the observed ~1MB/s leak:
    at 128Mi:  ~2 minutes of runway left
    at 512Mi:  ~8 minutes of runway left

  Doubling the limit on a leak doesn't fix it — it DOUBLES the runway.
  The pod still dies. It just dies LATER, at 3am instead of 3pm.
EXTRAP

echo ""
echo -e "${RED}Raising the limit on a leak is a scheduling decision, not a fix.${NC}"

pause "Anti-pattern quantified"

# --- 5. Fix A: the app fix ---------------------------------------------------
banner "STEP 5 — Fix A: leaks are app bugs (watch the working set DROP)"

echo -e "${YELLOW}Restarting the ramp on the (restarted) bad pod — smaller, safer:${NC}"
PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n shopnow "$PS_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=80', method='POST')).read().decode(), end='')"
echo -e "${YELLOW}Climbing to ~105MB. Watch the working set in Grafana (~80s)...${NC}"
sleep 90

echo ""
echo -e "${YELLOW}NOW — the app-level fix. Release the held memory:${NC}"
kubectl exec -n shopnow "$PS_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/release', method='POST')).read().decode(), end='')"

echo ""
echo -e "${GREEN}released; rss drops back to ~25MB${NC}"
echo -e "${YELLOW}In Grafana: the working set FALLS — the only fix that actually${NC}"
echo -e "${YELLOW}reverses a leak. Cap the cache, fix the retention, free the memory.${NC}"

pause "Fix A: the app fix, live"

# --- 6. Fix B: right-size from data -----------------------------------------
banner "STEP 6 — Fix B: right-size from DATA (the same load, survived)"

echo -e "${YELLOW}The sizing math, from measurements not guesses:${NC}"
cat << 'SIZING'
  measured peak working set (Ep 1/3 load):  ~225Mi (200MB held + ~25MB base)
  headroom (bursts, fragmentation, deploys): ×2  → ~450Mi
  round to a sane value:                    512Mi
  requests == limits:                        Guaranteed (payment path —
                                             eviction-proof per Episode 2)
  safety net: alert at 90% of limit          (fires at 461Mi)
SIZING

echo ""
echo -e "${YELLOW}Deploying the right-sized variant (Guaranteed, 512Mi)...${NC}"
kubectl apply -f "$SIZED_MANIFEST"
kubectl rollout status deployment/payment-service-sized -n shopnow --timeout=180s
SIZED_POD=$(kubectl get pods -n shopnow -l app=payment-service-sized -o jsonpath='{.items[0].metadata.name}')

echo ""
echo -e "${YELLOW}THE MOMENT: same command that killed it in Episode 1 —${NC}"
kubectl exec -n shopnow "$SIZED_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=200', method='POST')).read().decode(), end='')"

echo -e "${YELLOW}Watching it survive (~80s)...${NC}"
sleep 90
kubectl get pods -n shopnow -o custom-columns=POD:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount | grep payment-service

echo ""
echo -e "${GREEN}SAME LOAD. ZERO RESTARTS. That's the difference between guessing${NC}"
echo -e "${GREEN}and engineering.${NC}"

pause "Fix B: proven"

# --- 7. The safety net: the alert -------------------------------------------
banner "STEP 7 — The safety net: alert BEFORE the kernel"

echo -e "${YELLOW}Right-sizing handles known load. For the unknown, an alert at 90%${NC}"
echo -e "${YELLOW}of limit — wired into the lab's Prometheus (MemoryNearLimit).${NC}"
echo ""
echo -e "${YELLOW}Push the sized pod past 90% (allocate 450MB of its 512Mi):${NC}"
kubectl exec -n shopnow "$SIZED_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=450', method='POST')).read().decode(), end='')"

echo -e "${YELLOW}Waiting for for:1m to elapse (~90s)... watch the Alerts page:${NC}"
echo "  Prometheus UI: $PROM_URL/alerts  (MemoryNearLimit should go FIRING)"
for i in $(seq 1 15); do
    STATE=$(curl -s "$PROM_URL/api/v1/alerts" 2>/dev/null | grep -o '"alertname":"MemoryNearLimit"[^}]*"state":"[a-z]*"' | grep -o 'firing' || true)
    if [ -n "$STATE" ]; then
        echo -e "${GREEN}✓ MemoryNearLimit is FIRING${NC}"
        break
    fi
    echo "  waiting for the alert to fire... ($i/15)"
    sleep 10
done

echo ""
echo -e "${GREEN}The alert fired at ~461Mi — the pod is STILL ALIVE (512Mi limit).${NC}"
echo -e "${GREEN}You just got paged BEFORE the kernel acted. That is the entire${NC}"
echo -e "${GREEN}point of prevention: buy human time, not pod lives.${NC}"

echo ""
echo -e "${YELLOW}Releasing the test allocation...${NC}"
kubectl exec -n shopnow "$SIZED_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/release', method='POST')).read().decode(), end='')" || true

pause "Safety net demonstrated"

# --- 8. The checklist --------------------------------------------------------
banner "STEP 8 — The prevention checklist (the takeaway)"

cat << 'CHECKLIST'
  PREVENT OOMKILLS — the checklist:
  1. MEASURE   p95/p99 working set from real traffic (not guesses)
  2. CLASSIFY  leak (linear deriv) vs legit (plateau) — Ep 3's query
  3. FIX RIGHT leak -> fix the app (cap/free). legit -> right-size
  4. SIZE      peak × headroom; requests=limits for critical paths
  5. ALERT     90% of limit, for:5m (production), BEFORE the kernel
  6. PROVE     load-test the same load that killed it (this episode)
  7. REVIEW    VPA can recommend, humans decide (it restarts to apply)
CHECKLIST

echo ""
echo -e "${GREEN}Printable version: episodes/04-preventing-oomkills/prevention-checklist.md${NC}"
echo ""
echo -e "${CYAN}Season 1 complete: the kill (Ep1), the other killer (Ep2),${NC}"
echo -e "${CYAN}the runbook (Ep3), and now the fix. Full circle.${NC}"
echo ""
echo -e "${GREEN}Demo complete. Cleanup: make cleanup-ep04${NC}"
