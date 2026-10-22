#!/bin/bash
# Episode 1 cleanup — removes the episode workloads only.
# Crossplane itself (crossplane-system, providers, functions) stays installed.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

echo -e "${YELLOW}Removing Episode 1 workloads...${NC}"

kubectl delete -f "$EP_DIR/manifests/04-webapp.yaml" --ignore-not-found
kubectl delete -f "$EP_DIR/manifests/01-managed-resources.yaml" --ignore-not-found
kubectl delete namespace payments-team --ignore-not-found 2>/dev/null || true
kubectl delete namespace demo-team-a --ignore-not-found 2>/dev/null || true

# Keep the XRD + Composition installed: they are the "platform" the lab built.
# Uncomment to remove them too:
# kubectl delete -f "$EP_DIR/manifests/03-composition.yaml" --ignore-not-found
# kubectl delete -f "$EP_DIR/manifests/02-xrd.yaml" --ignore-not-found

echo -e "${GREEN}✓ Episode 1 cleaned up${NC}"
echo -e "${GREEN}✓ Crossplane still installed (make crossplane-uninstall to remove it)${NC}"
