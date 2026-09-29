#!/bin/bash
# =============================================================================
# Episode 2 — OOMKilled vs Evicted: They Are NOT the Same
#
# Flow:
#   1. Preflight: discover a worker node, ensure payment-service is running
#   2. Deploy BestEffort memory hogs pinned to that worker
#   3. Baseline: node memory is healthy
#   4. Trigger: ramp hog memory in rounds until the node crosses its
#      eviction threshold (memory.available) and the KUBELET evicts them
#   5. The contrast: hogs Evicted (node-level killer) vs payment-service
#      OOMKilled (per-container kernel killer) — two victims, two killers
#
# The target node is discovered dynamically — nothing is hardcoded.
# Eviction timing is NOT deterministic (kubelet housekeeping interval):
# the script polls instead of promising exact timing.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$EP_DIR/manifests/memory-hog.yaml"
EP1_MANIFEST="$EP_DIR/../01-oom-killed/manifests/payment-service.yaml"
NS="eviction-demo"
NODE=""
RAMP_MB_PER_ROUND=256      # per hog, per round
MAX_ROUNDS=10
ALLOC_TIMEOUT=300          # seconds to wait for each round's allocations

pause() { echo -e "\n${YELLOW}>>> $1 — press Enter to continue${NC}"; read -r; }
banner() { echo -e "\n${CYAN}===================================================================$NC"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}===================================================================$NC}"; }

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

banner "EPISODE 2: OOMKilled vs Evicted — They Are NOT the Same"

# --- 1. Preflight ------------------------------------------------------------
banner "STEP 1 — Preflight: pick the victim node, check the control workload"

# Pick the first worker node (agent role)
NODE=$(kubectl get nodes -l node-role.kubernetes.io/agent -o jsonpath='{.items[0].metadata.name}')
if [ -z "$NODE" ]; then
    # fallback: any node that isn't the control-plane
    NODE=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -v -i master | head -1)
fi
echo -e "${GREEN}Target node (eviction victim):${NC} $NODE"
echo -e "${YELLOW}Node memory before we start:${NC}"
kubectl top node "$NODE"

# Ensure Episode 1's payment-service is running (the contrast victim)
if kubectl get deployment payment-service -n shopnow &>/dev/null; then
    echo -e "${GREEN}✓ payment-service (Episode 1 workload) already running${NC}"
else
    echo -e "${YELLOW}Deploying payment-service (Episode 1 workload) for the contrast...${NC}"
    kubectl apply -f "$EP1_MANIFEST"
    kubectl rollout status deployment/payment-service -n shopnow --timeout=180s
fi

pause "Baseline captured"

# --- 2. Deploy the memory hogs ----------------------------------------------
banner "STEP 2 — Deploy BestEffort memory hogs on $NODE"

# Substitute the node name into the manifest (placeholder pattern)
sed "s/__WORKER_NODE__/$NODE/" "$MANIFEST" | kubectl apply -f -

echo -e "${YELLOW}Waiting for hog pods to be ready...${NC}"
kubectl rollout status deployment/memory-hog -n "$NS" --timeout=180s

echo -e "${YELLOW}Hog pods:${NC}"
kubectl get pods -n "$NS" -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,QOS:.status.qosClass

echo -e "${YELLOW}NOTE: QoS class is BestEffort — no requests, no limits.${NC}"
echo -e "${YELLOW}The kernel will never OOMKill these per-container (no limit to hit).${NC}"
echo -e "${YELLOW}Only the NODE running out of memory can kill them — via the kubelet.${NC}"

pause "Hogs deployed"

# --- 3. Baseline: node is healthy -------------------------------------------
banner "STEP 3 — Baseline: node conditions (no pressure yet)"

kubectl describe node "$NODE" | grep -A 6 "Conditions:"

echo -e "${YELLOW}MemoryPressure is False. The eviction threshold has not been crossed.${NC}"

pause "Watch this in Grafana: node memory available vs the threshold line"

# --- 4. Trigger: ramp the hogs ----------------------------------------------
banner "STEP 4 — Trigger: fill the node (watch memory.available fall)"

# NOTE: the eviction threshold on the demo worker is configured to
# memory.available<1Gi (see lab-guide). With the kubelet default
# (<100Mi) the demo still works — it just needs more rounds.

alloc_all_hogs() {
    local mb="$1"
    for pod in $(kubectl get pods -n "$NS" -l app=memory-hog -o jsonpath='{.items[*].metadata.name}'); do
        # only pods that are still Running (evicted pods can't allocate)
        if kubectl get pod -n "$NS" "$pod" -o jsonpath='{.status.phase}' | grep -q Running; then
            kubectl exec -n "$NS" "$pod" -- \
                python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=$mb', method='POST')).read().decode(), end='')" \
                || echo -e "${RED}(pod $pod gone — likely evicted)${NC}"
        fi
    done
}

evicted_count() {
    kubectl get pods -n "$NS" -o jsonpath='{range .items[*]}{.status.reason}{"\n"}{end}' 2>/dev/null | grep -c Evicted || true
}

echo -e "${YELLOW}Ramping ${RAMP_MB_PER_ROUND}MB per hog per round, checking the node after each round.${NC}"
echo -e "${YELLOW}(Eviction timing is kubelet-paced — the script polls for it.)${NC}"
echo ""

for round in $(seq 1 "$MAX_ROUNDS"); do
    EVICTED=$(evicted_count)
    if [ "$EVICTED" -gt 0 ]; then
        echo -e "${GREEN}✓ Eviction detected in round $((round-1)) — stopping the ramp${NC}"
        break
    fi
    echo -e "${CYAN}--- Round $round / $MAX_ROUNDS: +${RAMP_MB_PER_ROUND}MB per hog ---${NC}"
    alloc_all_hogs "$RAMP_MB_PER_ROUND"
    # wait for the gradual allocation (2MB/2s chunks) to mostly land
    echo -e "${YELLOW}waiting for allocation (~$((RAMP_MB_PER_ROUND/2*2))s)... node memory now:${NC}"
    sleep $((RAMP_MB_PER_ROUND / 2 * 2))
    kubectl top node "$NODE" || true
done

# --- 5. The eviction ---------------------------------------------------------
banner "STEP 5 — The eviction: wait for the kubelet to act"

for i in $(seq 1 30); do
    EVICTED=$(evicted_count)
    if [ "$EVICTED" -gt 0 ]; then
        echo -e "${GREEN}✓ $EVICTED hog pod(s) EVICTED${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}✗ No eviction after polling. Check the threshold config (lab-guide)${NC}"
        echo -e "${YELLOW}  and whether the ramp actually filled the node (kubectl top node)${NC}"
    fi
    echo -e "  waiting for kubelet eviction... ($i/30)"
    sleep 10
done

echo ""
echo -e "${YELLOW}Hog pods now (STATUS/REASON):${NC}"
kubectl get pods -n "$NS" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,REASON:.status.reason,NODE:.spec.nodeName

echo ""
echo -e "${YELLOW}The eviction events (the smoking gun):${NC}"
kubectl get events -n "$NS" --sort-by=.lastTimestamp | grep -i -E "evict|low on resource" | tail -10 || echo "(no eviction events found)"

pause "Eviction captured"

# --- 6. Investigation --------------------------------------------------------
banner "STEP 6 — Investigate: who died, who survived, and why"

EVICTED_POD=$(kubectl get pods -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.reason}{"\n"}{end}' | grep Evicted | head -1 | awk '{print $1}')
if [ -n "$EVICTED_POD" ]; then
    echo -e "${YELLOW}Describe the evicted pod — note Status: Failed, Reason: Evicted:${NC}"
    kubectl describe pod -n "$NS" "$EVICTED_POD" | grep -B 2 -A 8 -E "^Status:|Reason:|Events:" | head -40
fi

echo ""
echo -e "${YELLOW}Node conditions now — MemoryPressure:${NC}"
kubectl describe node "$NODE" | grep -A 6 "Conditions:"

echo ""
echo -e "${YELLOW}The eviction ranking (who dies first):${NC}"
cat << 'RANKING'
  kubelet eviction order under memory pressure:
    1. BestEffort          (no requests)           <- the hogs
    2. Burstable            (by usage OVER requests)
    3. Guaranteed           (requests == limits)    <- protected
  (PriorityClass breaks ties within a tier)

  payment-service is Burstable, but its usage (~30MB) is BELOW its
  request (64Mi) — usage-over-requests is negative — so every BestEffort
  hog dies before it does. That is the QoS lesson of this episode.
RANKING

echo ""
echo -e "${YELLOW}Did payment-service survive? (it should have):${NC}"
kubectl get pods -n shopnow -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount

pause "Investigation complete"

# --- 7. The contrast: two victims, two killers -------------------------------
banner "STEP 7 — The money shot: OOMKilled vs Evicted, side by side"

echo -e "${YELLOW}Re-triggering payment-service's OOMKill (Episode 1's death)...${NC}"
PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n shopnow "$PS_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=200', method='POST')).read().decode(), end='')"

echo -e "${YELLOW}Waiting for the kernel to kill it (~2-4 min ramp, then SIGKILL)...${NC}"
for i in $(seq 1 40); do
    if kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null | grep -q OOMKilled; then
        echo -e "${GREEN}✓ payment-service OOMKilled (the kernel, per-container)${NC}"
        break
    fi
    sleep 10
done

echo ""
echo -e "${CYAN}===================== THE COMPARISON =====================${NC}"
kubectl get pods -n shopnow -o custom-columns=VICTIM1:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason
kubectl get pods -n "$NS" -o custom-columns=VICTIM2:.metadata.name,STATUS:.status.phase,REASON:.status.reason
echo ""
cat << 'TABLE'
  |                     | payment-service (OOMKilled) | memory-hog (Evicted)   |
  |---------------------|-----------------------------|------------------------|
  | Killer              | Linux kernel                | kubelet                |
  | Level               | one container (cgroup)     | whole pods (node)      |
  | Trigger             | own limit exceeded          | node memory.available  |
  | QoS protection      | none — any class dies       | everything — ranking   |
  | Pod after death     | Running, RESTARTS +1        | Failed, gone from node |
  | Evidence            | memory.events, dmesg        | events, node condition |
TABLE

echo ""
echo -e "${YELLOW}Metrics to watch in Grafana (see promql/queries.md):${NC}"
echo "  - node_memory_MemAvailable_bytes (the drain)"
echo "  - kube_node_status_condition{condition='MemoryPressure'}"
echo "  - kube_pod_status_reason{reason='Evicted'}"
echo "  - split view: Ep1 sawtooth vs Ep2 node drain"
echo ""
echo -e "${GREEN}Demo complete. Cleanup: make cleanup-ep02${NC}"
