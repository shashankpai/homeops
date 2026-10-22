#!/bin/bash
# Remove everything installed by install-crossplane.sh. The K3s lab itself
# (k8s-under-the-hood) is untouched.
set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

echo -e "${GREEN}Removing Crossplane series components...${NC}"

kubectl delete -f "$SCRIPT_DIR/providers/30-provider-config.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/providers/00-provider.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/providers/40-functions.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/providers/20-rbac.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/providers/10-runtime-config.yaml" --ignore-not-found

helm uninstall crossplane -n crossplane-system 2>/dev/null || true
kubectl delete namespace crossplane-system --ignore-not-found

echo -e "${GREEN}✓ Crossplane removed — lab still running${NC}"
