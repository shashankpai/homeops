#!/bin/bash
# Observability Episode 01 cleanup — a no-op by design.
#
# The Life of a Metric is READ-ONLY: no workloads deployed, no config
# changed, no cluster state touched. This script exists only so the
# make cleanup-obsNN pattern stays uniform across the arc.
set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

echo -e "${GREEN}✓ Nothing to clean — this episode is read-only by design${NC}"
echo -e "${GREEN}✓ (Optional: remove the 'Episode OBS-01' dashboard in Grafana if imported)${NC}"
