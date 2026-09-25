#!/bin/bash
# Episode 1 cleanup — removes the demo workload only.
# The lab (K3s, monitoring namespace, observability stack) stays running.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

echo -e "${YELLOW}Removing Episode 1 workloads (namespace: shopnow)...${NC}"
kubectl delete namespace shopnow --ignore-not-found

echo -e "${GREEN}✓ Episode 1 cleaned up${NC}"
echo -e "${GREEN}✓ Lab still running (monitoring namespace untouched)${NC}"
