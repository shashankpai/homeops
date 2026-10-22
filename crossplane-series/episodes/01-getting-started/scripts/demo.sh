#!/bin/bash
# =============================================================================
# Crossplane Series — Episode 1: Crossplane Getting Started
#
# Flow (assumes `make crossplane-install` has been run):
#   0. What did we install? (core pods, CRDs, provider, functions)
#   1. Managed resources: a Namespace + ConfigMap via provider-kubernetes
#   2. Drift, three attacks: delete -> heal; edit -> revert; delete MR -> cascade
#   3. Platform API: XRD + Composition -> `kind: WebApp`
#   4. Create a WebApp: one resource becomes a whole environment
#   5. Update: patch spec.replicas, watch the chain of control loops
#   6. Trace + cleanup-on-delete: `crossplane beta trace`, delete the WebApp
#
# Manual alternative: every command here is in lab-guide.md, section by section.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${KUBECONFIG:-}" ]; then
    export KUBECONFIG="$HOME/.kube/config-k8suth"
fi

pause() { echo -e "\n${YELLOW}>>> $1 — press Enter to continue${NC}"; read -r; }
banner() {
    echo -e "\n${CYAN}===================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}===================================================================${NC}"
}

banner "Step 0 — What is running?"
kubectl get pods -n crossplane-system
echo ""
echo "CRDs installed by Crossplane:"
kubectl get crd | grep crossplane | wc -l | xargs echo "  crossplane-related CRDs:"
kubectl get providers
kubectl get functions
pause "Point out: provider + functions are just... packages. CRDs created on install."

# =============================================================================
banner "Step 1 — First managed resource"
kubectl apply -f "$EP_DIR/manifests/01-managed-resources.yaml"
echo ""
echo "Watching READY / SYNCED conditions:"
kubectl get objects.kubernetes.crossplane.io
pause "Then show the real thing exists:"
kubectl get ns demo-team-a
kubectl -n demo-team-a get configmap welcome -o yaml | grep -A2 data
pause "Crossplane did what Terraform does — but with no state file, no plan, no CLI magic."

# =============================================================================
banner "Step 2 — Drift: fight the control plane"
echo "Deleting the ConfigMap out-of-band (like a human with kubectl):"
kubectl -n demo-team-a delete configmap welcome
echo ""
echo "Now watch Crossplane heal it (reconcile loop, every ~60s or on watch):"
for i in 1 2 3 4 5 6; do
    if kubectl -n demo-team-a get configmap welcome >/dev/null 2>&1; then
        echo -e "${GREEN}ConfigMap is back after ${i} checks — Crossplane won.${NC}"
        break
    fi
    echo "  check $i: not yet..."; sleep 5
done
kubectl -n demo-team-a get configmap welcome
pause "Attack 1 done (delete -> recreate). Terraform needs a plan run to notice. Crossplane never stops watching."

echo ""
echo "Attack 2 — EDIT instead of delete (the drift pipelines are blind to):"
kubectl -n demo-team-a patch configmap welcome \
    -p '{"data":{"message":"edited by a human, defiantly"}}'
echo "  defied. Now waiting for a reconcile to revert it (up to ~60s)..."
for i in $(seq 1 15); do
    MSG=$(kubectl -n demo-team-a get configmap welcome -o jsonpath='{.data.message}' 2>/dev/null || true)
    if echo "$MSG" | grep -q "Crossplane"; then
        echo -e "${GREEN}Reverted after ${i} checks — the edit was overwritten.${NC}"
        break
    fi
    sleep 5
done
kubectl -n demo-team-a get configmap welcome -o jsonpath='{.data.message}'; echo

echo ""
echo "Attack 3 — delete the MANAGED RESOURCE (the Crossplane object):"
kubectl delete object demo-team-a-welcome
kubectl -n demo-team-a get configmap welcome 2>&1 || true
echo -e "${GREEN}Cascade: removing the MR removed the real object (default removalPolicy: Delete).${NC}"
pause "For attack 3 in reverse (removalPolicy: Orphan) see lab-guide §13 — manual only."

# Recreate the ConfigMap MR so later steps stay consistent
kubectl apply -f "$EP_DIR/manifests/01-managed-resources.yaml"

# =============================================================================
banner "Step 3 — Build a platform API (XRD + Composition)"
kubectl apply -f "$EP_DIR/manifests/02-xrd.yaml"
echo ""
echo "Crossplane just created a brand-new Kubernetes kind:"
kubectl get crd webapps.demo.crossplane.io
pause "Show the Composition that defines what a WebApp means:"
kubectl apply -f "$EP_DIR/manifests/03-composition.yaml"
kubectl get composition webapp-standard

# =============================================================================
banner "Step 4 — The payoff: create a WebApp"
cat "$EP_DIR/manifests/04-webapp.yaml"
pause "Apply it, then watch an entire environment appear:"
kubectl apply -f "$EP_DIR/manifests/04-webapp.yaml"
kubectl get webapp payments -w &
WATCH_PID=$!
echo ""
echo "Composed resources (namespace + deployment + service + configmap):"
for i in $(seq 1 12); do
    if kubectl -n payments-team get deploy/webapp >/dev/null 2>&1; then break; fi
    sleep 5
done
kubectl -n payments-team get all,cm
kill $WATCH_PID 2>/dev/null || true
pause "One 9-line YAML. No namespace to create, no Deployment YAML to copy-paste."

# =============================================================================
banner "Step 5 — Update: patch the WebApp, watch the chain of loops"
echo "Patching spec.replicas 2 -> 4 (a chain fires: XR -> re-render -> composed Deployment -> rollout):"
kubectl patch webapp payments -n default --type merge -p '{"spec":{"replicas":4}}'
echo ""
echo "Watching the composed Deployment scale:"
for i in $(seq 1 12); do
    DESIRED=$(kubectl -n payments-team get deploy/webapp -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
    [ "$DESIRED" = "4" ] && break
    sleep 5
done
kubectl -n payments-team get deploy/webapp
pause "That was 'kubectl patch' scaling an environment. No pipeline ran."

# =============================================================================
banner "Step 6 — Trace it, then delete it"
if command -v crossplane >/dev/null; then
    crossplane beta trace webapp/payments -n default
else
    echo "(crossplane CLI not found — showing composed refs instead)"
    kubectl get webapp payments -n default -o yaml | grep -A5 "resourceRefs"
fi
pause "Now the scary-powerful part — delete the WebApp:"
kubectl delete webapp payments -n default
echo "Everything composed from it is deleted too:"
kubectl get ns payments-team 2>&1 || true
echo ""
echo -e "${GREEN}✓ Demo complete. Run 'make cleanup-ep01' to remove the rest.${NC}"
