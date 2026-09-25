#!/bin/bash
# =============================================================================
# Episode 1 — What REALLY happens when Kubernetes OOMKills a Pod?
#
# Flow:
#   1. Deploy the ShopNow Payment Service (128Mi memory limit)
#   2. Baseline: metrics look healthy
#   3. Trigger: /allocate?mb=200 pushes the working set past the limit
#   4. The kill: OOMKilled, exit code 137
#   5. Investigation across 5 layers:
#        Layer 1 — Kubernetes API (kubectl)
#        Layer 2 — Container runtime (crictl)
#        Layer 3 — cgroups (memory.max / memory.events)
#        Layer 4 — Kernel (dmesg, OOM killer log)
#        Layer 5 — Metrics (PromQL)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$EP_DIR/manifests/payment-service.yaml"
NS="shopnow"
POD=""

pause() { echo -e "\n${YELLOW}>>> $1 — press Enter to continue${NC}"; read -r; }
banner() { echo -e "\n${CYAN}===================================================================$NC"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}===================================================================${NC}"; }

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

banner "EPISODE 1: What REALLY happens when Kubernetes OOMKills a Pod?"

# --- 1. Deploy ----------------------------------------------------------------
banner "STEP 1 — Deploy the ShopNow Payment Service (limits: 128Mi)"

kubectl apply -f "$MANIFEST"
echo -e "${YELLOW}Waiting for the pod to be ready...${NC}"
# NOTE: `kubectl wait --for=condition=ready pod -l ...` can race the
# Deployment controller ("no matching resources found") — rollout status
# waits on the Deployment itself and cannot race.
kubectl rollout status deployment/payment-service -n "$NS" --timeout=180s
POD=$(kubectl get pods -n "$NS" -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl get pod -n "$NS" "$POD" -o jsonpath='{.spec.nodeName}')

echo -e "${GREEN}Pod:${NC}  $POD"
echo -e "${GREEN}Node:${NC} $NODE"
kubectl get pod -n "$NS" "$POD" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount

pause "Baseline check"

# --- 2. Baseline -------------------------------------------------------------
banner "STEP 2 — Baseline: everything looks healthy"

echo -e "${YELLOW}Memory usage (reported by the app):${NC}"
kubectl exec -n "$NS" "$POD" -- python -c "print(open('/proc/self/status').read())" 2>/dev/null | grep -E "^(VmRSS|VmHWM)" || true
# NOTE: the pod image (python:3.12-slim) has no curl/wget — use python's
# urllib for the app's HTTP endpoints.
kubectl exec -n "$NS" "$POD" -- python -c 'import urllib.request as u; print(u.urlopen("http://localhost:8080/usage").read().decode(), end="")'

echo ""
echo -e "${YELLOW}Pod top (metrics-server view):${NC}"
kubectl top pod -n "$NS" 2>/dev/null || echo "(metrics-server may take a moment)"

echo ""
echo -e "${YELLOW}The limit, as the kernel sees it (cgroup memory.max):${NC}"
kubectl exec -n "$NS" "$POD" -- cat /sys/fs/cgroup/memory.max 2>/dev/null \
  || echo "134217728 (128Mi) — not readable from inside (read-only rootfs is fine)"

pause "Now trigger the OOM"

# --- 3. Trigger --------------------------------------------------------------
banner "STEP 3 — Trigger: POST /allocate?mb=200 (past the 128Mi limit)"

echo -e "${YELLOW}Telling the payment service to allocate 200MB and hold it...${NC}"
kubectl exec -n "$NS" "$POD" -- python -c 'import urllib.request as u; print(u.urlopen(u.Request("http://localhost:8080/allocate?mb=200", method="POST")).read().decode(), end="")' || true

echo ""
echo -e "${YELLOW}Watching for the OOMKill (exit code 137)...${NC}"
echo -e "${YELLOW}The next RESTART count / OOMKilled line is the moment of death.${NC}"

# Watch until restart count increments (timeout 120s)
BASE_RESTARTS=$(kubectl get pod -n "$NS" "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')
DEADLINE=$((SECONDS + 120))
while [ $SECONDS -lt $DEADLINE ]; do
    RESTARTS=$(kubectl get pod -n "$NS" "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "x")
    if [ "$RESTARTS" != "$BASE_RESTARTS" ]; then
        echo -e "${RED}>>> Container was killed and restarted! (restarts: $BASE_RESTARTS -> $RESTARTS)${NC}"
        break
    fi
    sleep 2
done

if [ "${RESTARTS:-}" = "$BASE_RESTARTS" ]; then
    echo -e "${RED}Container did not get OOMKilled within 120s — check: kubectl describe pod -n $NS $POD${NC}"
    exit 1
fi

pause "The pod is dead (and reborn). Investigate."

# --- 4. Layer 1: Kubernetes API ----------------------------------------------
banner "LAYER 1 — Kubernetes API: kubectl describe pod"

kubectl describe pod -n "$NS" "$POD" | sed -n '/Containers:/,/Conditions:/p' | head -30

echo -e "${YELLOW}Key lines to read:${NC}"
kubectl get pod -n "$NS" "$POD" -o jsonpath='{.status.containerStatuses[0].lastState}' | python3 -m json.tool 2>/dev/null || \
kubectl get pod -n "$NS" "$POD" -o jsonpath='{.status.containerStatuses[0].lastState}'

echo ""
echo -e "${GREEN}>>> Last State: Terminated | Reason: OOMKilled | Exit Code: 137${NC}"
echo -e "${GREEN}>>> 137 = 128 (killed by signal) + 9 (SIGKILL). Kubernetes didn't do this — the kernel did.${NC}"

pause "Go below the API, into the node: the container runtime"

# --- 5. Layer 2: container runtime -------------------------------------------
banner "LAYER 2 — Container runtime (crictl) on node: $NODE"

echo -e "${YELLOW}What Kubernetes tells you is a summary. The container runtime (containerd)
on the node saw the raw event. Run these ON THE NODE:${NC}"
echo ""
cat << EOF
  ssh \$NODE_USER@$NODE   (or: kubectl debug node/$NODE -it --image=busybox -- chroot /host crictl ...)

    # All containers including dead ones:
    crictl ps -a | grep payment-service

    # The dead container's exit code and reason:
    crictl inspect \$(crictl ps -a -q --name payment-service | head -1) | \\
      jq '.status.exitCode, .status.reason, .status.startedAt, .status.finishedAt'

    # NOTE: containerd may have already removed the dead container —
    # Kubernetes keeps the pod object, but the runtime GC's the container.
EOF

pause "Below the runtime: the cgroup where the limit actually lives"

# --- 6. Layer 3: cgroups -----------------------------------------------------
banner "LAYER 3 — cgroups: where the 128Mi limit REALLY lives"

echo -e "${YELLOW}The Deployment's 'limits.memory: 128Mi' becomes a cgroup file on the node:${NC}"
cat << EOF
  On node $NODE. NOTE: on K3s cgroup paths use the POD UID (not the
  namespace), and crictl's runtimeSpec.cgroupsPath is often null —
  derive the path from the pod UID instead:

    # on your workstation — get the pod UID
    POD_UID=\$(kubectl get pod -n shopnow $POD -o jsonpath='{.metadata.uid}')

    # on the node — the pod's cgroup slice (burstable QoS for this demo)
    CG=/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod\${POD_UID//-/_}.slice

    cat \$CG/memory.max       <- 134217728  (= 128Mi, the limit)
    cat \$CG/memory.current   <- usage at any moment
    cat \$CG/memory.events    <- oom_kill counter! Non-zero = kernel killed here

  >>> memory.events is the smoking gun: when oom_kill increments,
      the kernel OOM killer selected a process INSIDE this cgroup.
      The pod-level slice survives container restarts (the per-container
      scope is GC'd quickly) — that's where the evidence stays.
EOF

pause "Below cgroups: the kernel itself"

# --- 7. Layer 4: kernel ------------------------------------------------------
banner "LAYER 4 — Kernel: dmesg, the OOM killer's own log"

cat << EOF
  On node $NODE:

    dmesg -T | grep -i -A3 'out of memory'

  You'll see something like:

    Out of memory: Killed process 12345 (python) total-vm:... anon-rss:...
      oom_reaper or oom_kill_process lines naming the exact PID

  >>> This is the truth. The kernel memory allocator couldn't satisfy the
      cgroup limit, invoked the OOM killer, which picked the single process
      in the cgroup (our python app) and sent SIGKILL.
      SIGKILL cannot be caught, blocked, or ignored. Exit code 137.
EOF

pause "Finally: see it in the metrics"

# --- 8. Layer 5: metrics -----------------------------------------------------
banner "LAYER 5 — Metrics: PromQL (the visual version of everything above)"

echo -e "${YELLOW}Open Prometheus/Grafana:${NC}"
cat << EOF
  Prometheus: http://192.168.1.81:30900   (any node IP; LoadBalancer, no port-forward)
  Grafana:    http://192.168.1.81:30300   (any node IP; admin/admin)

  In Grafana: Dashboards -> Import -> episodes/01-oom-killed/dashboards/oom-investigation.json

  Queries to run (see episodes/01-oom-killed/promql/queries.md):

    1. container_memory_working_set_bytes{namespace="shopnow"}
       vs container_spec_memory_limit_bytes{namespace="shopnow"}
       -> the line hits the ceiling, then drops (the kill), then restarts low

    2. kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
       -> flips to 1

    3. increase(container_oom_events_total{namespace="shopnow"}[10m])
       -> the kernel's own kill counter, from cAdvisor
EOF

pause "Wrap up"

# --- 9. Recap ----------------------------------------------------------------
banner "RECAP — the 5 layers of an OOMKill"

cat << EOF
  1. KUBERNETES API   kubectl describe pod  ->  "OOMKilled, Exit Code 137"
                       (a SUMMARY written after the fact)
  2. RUNTIME          crictl inspect        ->  exit code 137, reason: OOMKilled
                       (containerd saw the process die)
  3. CGROUPS          memory.max            ->  134217728 (your 128Mi limit)
                       memory.events        ->  oom_kill: 1
                       (the courtroom where the limit is enforced)
  4. KERNEL           dmesg                 ->  "Out of memory: Killed process..."
                       (the executioner — OOM killer sent SIGKILL)
  5. METRICS          PromQL                ->  working set vs limit, the sawtooth
                       (the historical record, visible AFTER the fact)

  KEY INSIGHT: Kubernetes NEVER kills the container. It wrote a limit into a
  cgroup file and walked away. The KERNEL's OOM killer pulled the trigger.
  137 = 128 + 9 = killed-by-signal SIGKILL.

  Next episode: OOMKilled vs Evicted — they are NOT the same thing.
EOF

echo -e "\n${GREEN}Episode 1 demo complete.${NC}"
echo -e "${YELLOW}Cleanup (keep the lab): make cleanup-ep01${NC}"
