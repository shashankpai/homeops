#!/bin/bash
# Health check for the Crossplane install + the K3s lab underneath.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo -e "${GREEN}Nodes:${NC}"
kubectl get nodes || fail "Cannot reach lab"

echo -e "\n${GREEN}Crossplane core:${NC}"
kubectl get pods -n crossplane-system || fail "crossplane-system namespace missing — run make crossplane-install"

echo -e "\n${GREEN}Providers / Functions:${NC}"
kubectl get providers || true
kubectl get functions || true

echo -e "\n${GREEN}ProviderConfig:${NC}"
kubectl get providerconfigs.kubernetes.crossplane.io || true

echo ""
echo -e "${GREEN}All checks displayed. Everything above should show Running/Healthy/True.${NC}"
