#!/bin/bash
# Install Crossplane v2 + provider-kubernetes + composition functions
# into the k8s-under-the-hood K3s lab. Idempotent; safe to re-run.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/versions.env"

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

banner() {
    echo -e "\n${GREEN}=================================================================${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}=================================================================${NC}"
}

banner "Step 0/4 — Checking lab access"
kubectl get nodes >/dev/null 2>&1 || fail "Cannot reach the lab (KUBECONFIG=$KUBECONFIG). Run ../k8s-under-the-hood/make setup first."
kubectl get nodes

banner "Step 1/4 — Installing Crossplane chart ${CROSSPLANE_CHART_VERSION}"
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system --create-namespace \
    --version "$CROSSPLANE_CHART_VERSION" \
    --wait --timeout 5m

banner "Step 2/4 — Applying RBAC + runtime config (before the Provider so the SA exists)"
kubectl apply -f "$SCRIPT_DIR/providers/10-runtime-config.yaml"
kubectl apply -f "$SCRIPT_DIR/providers/20-rbac.yaml"

banner "Step 3/4 — Installing provider-kubernetes + functions"
# sed the pinned package versions into the manifests at apply time
for f in "$SCRIPT_DIR/providers/00-provider.yaml" "$SCRIPT_DIR/providers/40-functions.yaml"; do
    sed -e "s|provider-kubernetes:v1.0.0|provider-kubernetes:${PROVIDER_KUBERNETES_VERSION}|" \
        -e "s|function-patch-and-transform:v0.10.0|function-patch-and-transform:${FUNCTION_PNT_VERSION}|" \
        -e "s|function-auto-ready:v0.5.0|function-auto-ready:${FUNCTION_AUTO_READY_VERSION}|" \
        "$f" | kubectl apply -f -
done

banner "Step 4/4 — Waiting for provider + functions to become healthy"
echo -e "${YELLOW}Provider packages are pulled from xpkg.upbound.io — first install can take ~60s.${NC}"
kubectl wait --for=condition=Healthy provider/provider-kubernetes --timeout=300s || fail "Provider did not become Healthy"
kubectl wait --for=condition=Healthy function/function-patch-and-transform --timeout=300s || fail "function-patch-and-transform not Healthy"
kubectl wait --for=condition=Healthy function/function-auto-ready --timeout=300s || fail "function-auto-ready not Healthy"

kubectl apply -f "$SCRIPT_DIR/providers/30-provider-config.yaml"

echo ""
echo -e "${GREEN}✓ Crossplane installed${NC}"
kubectl get pods -n crossplane-system
