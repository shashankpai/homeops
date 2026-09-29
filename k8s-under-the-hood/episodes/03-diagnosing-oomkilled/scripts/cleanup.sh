#!/bin/bash
# Episode 3 cleanup — removes the CrashLoop contrast pod only.
# payment-service (Episode 1 workload) and the lab stay running.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

echo -e "${YELLOW}Removing Episode 3 workloads (namespace: crashloop-demo)...${NC}"
kubectl delete namespace crashloop-demo --ignore-not-found

echo -e "${GREEN}✓ Episode 3 cleaned up${NC}"
echo -e "${GREEN}✓ Lab still running; payment-service untouched${NC}"
echo -e "${YELLOW}(payment-service may still show a restart from the demo kill —${NC}"
echo -e "${YELLOW} that's the evidence, not a problem)${NC}"
