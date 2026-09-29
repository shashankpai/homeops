#!/bin/bash
# =============================================================================
# Episode 3 — How do you actually diagnose an OOMKilled Pod?
#
# The runbook episode: ONE fresh kill, investigated start-to-finish with a
# repeatable, ordered checklist — plus a CrashLoopBackOff contrast pod so
# the triage fork (OOMKilled vs Evicted vs CrashLoop) is shown live.
#
# Flow:
#   1. Preflight: payment-service (OOMKilled victim) + crashy (CrashLoop victim)
#   2. Triage: the 30-second fork (STATUS / RESTARTS / REASON)
#   3. False leads: why logs mislead in BOTH directions
#   4. Layer 1 — API (describe + exit code decode)
#   5. Layer 2 — Metrics (the objective evidence — observability phase)
#   6. Layer 3 — Node (cgroup memory.events)
#   7. Layer 4 — Kernel (dmesg — and when to stop before needing it)
#   8. The evidence matrix + runbook handoff
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$EP_DIR/manifests/crashloop.yaml"
EP1_MANIFEST="$EP_DIR/../01-oom-killed/manifests/payment-service.yaml"
LAB_SSH_KEY="${LAB_SSH_KEY:-$EP_DIR/../../../lab/ssh/id_rsa}"

pause() { echo -e "\n${YELLOW}>>> $1 — press Enter to continue${NC}"; read -r; }
banner() { echo -e "\n${CYAN}===================================================================$NC"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}===================================================================$NC}"; }

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

banner "EPISODE 3: How do you actually diagnose an OOMKilled Pod?"

# --- 1. Preflight ------------------------------------------------------------
banner "STEP 1 — Preflight: stage the two victims"

if kubectl get deployment payment-service -n shopnow &>/dev/null; then
    echo -e "${GREEN}✓ payment-service (Episode 1 workload) already running${NC}"
else
    echo -e "${YELLOW}Deploying payment-service (Episode 1 workload)...${NC}"
    kubectl apply -f "$EP1_MANIFEST"
    kubectl rollout status deployment/payment-service -n shopnow --timeout=180s
fi

echo -e "${YELLOW}Deploying the CrashLoop contrast pod (crashy)...${NC}"
kubectl apply -f "$MANIFEST"
echo -e "${YELLOW}Waiting for both victims to get into trouble (~90s)...${NC}"
sleep 90

# Kill payment-service fresh so we diagnose a NEW death, not a stale one
PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
echo -e "${YELLOW}Triggering a fresh OOMKill on payment-service...${NC}"
kubectl exec -n shopnow "$PS_POD" -- \
    python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/allocate?mb=200', method='POST')).read().decode(), end='')"
echo -e "${YELLOW}Waiting for the kernel to act (gradual ramp, ~3-4 min)...${NC}"
for i in $(seq 1 40); do
    if kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null | grep -q OOMKilled; then
        echo -e "${GREEN}✓ Fresh OOMKill ready to diagnose${NC}"
        break
    fi
    sleep 10
done

pause "Crime scene staged"

# --- 2. Triage: the 30-second fork ------------------------------------------
banner "STEP 2 — Triage: the 30-second fork (before you type anything else)"

echo -e "${YELLOW}One command, three columns, three different families:${NC}"
echo ""
kubectl get pods -A -o custom-columns=\
NS:.metadata.namespace,\
POD:.metadata.name,\
STATUS:.status.phase,\
RESTARTS:.status.containerStatuses[0].restartCount,\
LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason,\
WAITING-REASON:.status.containerStatuses[0].state.waiting.reason \
    | grep -E "NAMESPACE|payment-service|crashy|eviction" || true

echo ""
cat << 'TRIAGE'
  READ IT LIKE THIS:
    RESTARTS climbing + LAST-REASON: OOMKilled -> container limit (Episode 1)
    WAITING-REASON: CrashLoopBackOff -> the APP fails to start (this pod)
    STATUS: Failed + REASON: Evicted  -> node pressure (Episode 2)

  30 seconds, zero investigation commands, and you already know:
    - WHICH layer to investigate (container / app / node)
    - WHICH episode's runbook to open
TRIAGE

pause "Triage done — you know the family before the autopsy"

# --- 3. False leads ----------------------------------------------------------
banner "STEP 3 — The false leads: why logs mislead in BOTH directions"

echo -e "${YELLOW}Logs of the OOMKilled pod (the victim we care about):${NC}"
kubectl logs -n shopnow "$PS_POD" --previous 2>&1 | tail -5 || \
    kubectl logs -n shopnow "$PS_POD" 2>&1 | tail -5 || echo "(no logs at all)"
echo ""
echo -e "${RED}No exception. No stack trace. No goodbye.${NC}"
echo -e "${YELLOW}SIGKILL kills the process between two lines of output — the log${NC}"
echo -e "${YELLOW}CANNOT contain the failure. Empty logs on a dead pod is a HINT${NC}"
echo -e "${YELLOW}(an OOMKill hint), not a dead end.${NC}"

echo ""
echo -e "${YELLOW}Now the CrashLoop pod's logs (looks similar in the pod list!):${NC}"
kubectl logs -n crashloop-demo crashy --previous 2>&1 | tail -3 || \
    kubectl logs -n crashloop-demo crashy 2>&1 | tail -3

echo ""
echo -e "${GREEN}Total opposite: the CrashLoop pod's logs TELL you the answer${NC}"
echo -e "${GREEN}('FAILED: exit 1' — an app problem, not a memory problem).${NC}"
echo ""
echo -e "${YELLOW}THE RULE: logs-first debugging works for CrashLoopBackOff and${NC}"
echo -e "${YELLOW}fails silently for OOMKilled. Triage FIRST (Step 2), then logs.${NC}"

pause "False leads mapped"

# --- 4. Layer 1: the API -----------------------------------------------------
banner "STEP 4 — Layer 1: the Kubernetes API (the after-action report)"

kubectl describe pod -n shopnow "$PS_POD" | grep -B 3 -A 6 -E "Last State|Reason|Exit Code|Restart Count"

echo ""
echo -e "${YELLOW}Decode the exit code:${NC}"
cat << 'DECODE'
  Exit Code: 137  ->  128 + 9
    128 = "killed by a signal"
      9 = SIGKILL — cannot be caught, cannot be ignored
  Only two things send SIGKILL to a container:
    the kernel's OOM killer (container limit)   <- LAST-REASON says OOMKilled
    kubelet (liveness probe failures)           <- LAST-REASON says something else
DECODE

echo ""
echo -e "${YELLOW}Stop-check: API told us WHO (kernel) and WHY (limit). If you only${NC}"
echo -e "${YELLOW}needed the family, you can stop here. The next layers answer:${NC}"
echo -e "${YELLOW}'was it a leak or legit load?' and 'how close to the limit were we?'${NC}"

pause "API layer complete"

# --- 5. Layer 2: metrics ----------------------------------------------------
banner "STEP 5 — Layer 2: Metrics (the objective evidence)"

echo -e "${YELLOW}Three queries tell you everything about the death:${NC}"
echo ""
echo "  1) Was the last death really an OOMKill (API view, from metrics):"
echo "     kube_pod_container_status_last_terminated_reason{reason='OOMKilled'}"
echo ""
echo "  2) How close to the limit, in the minutes before death:"
echo "     container_memory_working_set_bytes / container_spec_memory_limit_bytes"
echo ""
echo "  3) How FAST was it climbing (leak signature vs plateau):"
echo "     deriv(container_memory_working_set_bytes[10m])"
echo ""
echo -e "${YELLOW}In Prometheus/Grafana (Episode 3 dashboard):${NC}"
echo "   Prometheus: http://192.168.1.81:30900  (any node IP)"
echo "   Grafana:    http://192.168.1.81:30300  (admin/admin)"
echo "   Dashboard:  'Episode 3 — OOMKill Diagnosis'"
echo ""
echo -e "${YELLOW}The read: working set climbed LINEARLY to the 128Mi limit and fell${NC}"
echo -e "${YELLOW}off a cliff at the kill. Linear climb = leak signature (a legit cache${NC}"
echo -e "${YELLOW}warm-up plateaus). That distinction decides the FIX — next episode.${NC}"

pause "Metrics layer complete"

# --- 6. Layer 3: the node ---------------------------------------------------
banner "STEP 6 — Layer 3: on the node (cgroup memory.events)"

PS_POD_UID=$(kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.metadata.uid}')
NODE_NAME=$(kubectl get pod -n shopnow "$PS_POD" -o jsonpath='{.spec.nodeName}')
NODE_IP=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
CG="/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod${PS_POD_UID//-/_}.slice"

echo -e "${GREEN}Pod:${NC} $PS_POD  ${GREEN}Node:${NC} $NODE_NAME ($NODE_IP)"
echo -e "${YELLOW}The pod's cgroup (survives container restarts):${NC} $CG"
echo ""

echo -e "${YELLOW}The kernel's own kill counter — read FROM the node:${NC}"
ssh -i "$LAB_SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@$NODE_IP" \
    "echo 'memory.max:'; cat $CG/memory.max; echo 'memory.events:'; cat $CG/memory.events" 2>/dev/null || {
    echo -e "${RED}(SSH to node failed — run manually: ssh -i lab/ssh/id_rsa ubuntu@$NODE_IP)${NC}"
    echo -e "${YELLOW}  cat $CG/memory.max $CG/memory.events${NC}"
}

echo ""
echo -e "${YELLOW}oom_kill > 0 = the kernel's confession, in the kernel's own counter.${NC}"
echo -e "${YELLOW}Use this layer when the API/metrics view is contested or gone${NC}"
echo -e "${YELLOW}(e.g. pod deleted, dashboards down, 'was it REALLY an OOMKill?').${NC}"

pause "Node layer complete"

# --- 7. Layer 4: the kernel -------------------------------------------------
banner "STEP 7 — Layer 4: the kernel's log (dmesg) — and when to STOP"

echo -e "${YELLOW}The deepest evidence — only needed when you must see the kill${NC}"
echo -e "${YELLOW}itself (timestamps, process, kill score) — e.g. for a vendor${NC}"
echo -e "${YELLOW}escalation or a post-mortem exhibit:${NC}"
echo ""
ssh -i "$LAB_SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@$NODE_IP" \
    "sudo dmesg -T | grep -i -E 'out of memory|killed process' | tail -5" 2>/dev/null || {
    echo -e "${RED}(SSH to node failed — run manually:)${NC}"
    echo -e "${YELLOW}  ssh -i lab/ssh/id_rsa ubuntu@$NODE_IP 'sudo dmesg -T | grep -i killed'${NC}"
}

echo ""
echo -e "${CYAN}THE STOP RULE: investigate ONE layer deeper than you need, never five.${NC}"
echo -e "${YELLOW}  'It OOMKilled'                     -> stop at Layer 1 (API)${NC}"
echo -e "${YELLOW}  'Was it a leak or legit?'           -> stop at Layer 2 (metrics)${NC}"
echo -e "${YELLOW}  'Prove it was the kernel'           -> Layer 3 (memory.events)${NC}"
echo -e "${YELLOW}  'Exhibit A for the post-mortem'     -> Layer 4 (dmesg)${NC}"

pause "All four layers walked"

# --- 8. The evidence matrix --------------------------------------------------
banner "STEP 8 — The evidence matrix (what to run, what it proves)"

cat << 'MATRIX'
  | Layer      | Command                          | Answers                    | Cost |
  |------------|----------------------------------|----------------------------|------|
  | Triage     | kubectl get pods (custom-cols)   | which family of death      |  5s  |
  | Logs       | kubectl logs --previous          | CrashLoop only; EMPTY for  | 10s  |
  |            |                                  | OOMKilled (a hint, not a   |      |
  |            |                                  | dead end)                  |      |
  | 1 API      | kubectl describe pod             | who (kernel), why (limit)  | 10s  |
  | 2 Metrics  | last_terminated_reason, WS/limit | leak vs legit, how close   | 60s  |
  | 3 Node     | cat memory.events                | kernel's own counter       | 2min |
  | 4 Kernel   | dmesg                            | the kill itself, timestamp | 2min |
MATRIX

echo ""
echo -e "${GREEN}The full runbook (printable): episodes/03-diagnosing-oomkilled/runbook.md${NC}"
echo ""
echo -e "${YELLOW}Next: you know WHO killed it and WHY. Episode 4 is the engineering${NC}"
echo -e "${YELLOW}answer — how to make sure it never pages you again.${NC}"
echo ""
echo -e "${GREEN}Demo complete. Cleanup: make cleanup-ep03${NC}"
