#!/bin/bash
# Episode 2 cleanup — removes the eviction-demo workload only.
# The lab (K3s, monitoring namespace, observability stack) and Episode 1's
# payment-service stay running.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

echo -e "${YELLOW}Removing Episode 2 workloads (namespace: eviction-demo)...${NC}"
kubectl delete namespace eviction-demo --ignore-not-found

echo -e "${YELLOW}Waiting for the node to recover (MemoryPressure should clear)...${NC}"
for i in $(seq 1 12); do
    PRESSURE=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="MemoryPressure")].status}{" "}{end}')
    if ! echo "$PRESSURE" | grep -q True; then
        echo -e "${GREEN}✓ MemoryPressure cleared${NC}"
        break
    fi
    echo "  still under pressure... ($i/12)"
    sleep 10
done

echo -e "${GREEN}✓ Episode 2 cleaned up${NC}"
echo -e "${GREEN}✓ Lab still running; payment-service (Episode 1) untouched${NC}"
