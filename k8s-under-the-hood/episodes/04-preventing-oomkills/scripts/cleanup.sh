#!/bin/bash
# Episode 4 cleanup — removes the right-sized variant only.
# The bad payment-service (Episode 1 workload) and the lab stay running.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

echo -e "${YELLOW}Removing Episode 4 workloads (payment-service-sized)...${NC}"
kubectl delete deployment payment-service-sized -n shopnow --ignore-not-found

echo -e "${YELLOW}Releasing any held allocations on payment-service (app hygiene)...${NC}"
PS_POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$PS_POD" ]; then
    kubectl exec -n shopnow "$PS_POD" -- \
        python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/release', method='POST')).read().decode(), end='')" \
        2>/dev/null || echo "(nothing to release)"
fi

echo -e "${GREEN}✓ Episode 4 cleaned up${NC}"
echo -e "${GREEN}✓ Lab still running; payment-service (Episode 1) untouched${NC}"
echo -e "${YELLOW}(Alert rules stay loaded in Prometheus — they're lab infrastructure now)${NC}"
