#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== K8s Under the Hood Lab Verification ===${NC}"
echo ""

# Check kubeconfig
echo -e "${YELLOW}Checking kubeconfig...${NC}"

if [ -z "$KUBECONFIG" ]; then
    export KUBECONFIG=~/.kube/config-k8suth
fi

if [ ! -f "$KUBECONFIG" ]; then
    echo -e "${RED}✗ kubeconfig not found at $KUBECONFIG${NC}"
    echo -e "${YELLOW}Run 'make setup' first${NC}"
    exit 1
fi

echo -e "${GREEN}✓ kubeconfig found${NC}"
echo ""

# Check Kubernetes connectivity
echo -e "${YELLOW}Checking Kubernetes cluster...${NC}"

if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Connected to Kubernetes cluster${NC}"
echo ""

# Check nodes
echo -e "${YELLOW}Checking nodes...${NC}"

READY_NODES=$(kubectl get nodes --no-headers | grep -c "Ready" || true)
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)

if [ "$READY_NODES" -eq 3 ]; then
    echo -e "${GREEN}✓ All 3 nodes are Ready${NC}"
else
    echo -e "${RED}✗ Only $READY_NODES/$TOTAL_NODES nodes are Ready${NC}"
    kubectl get nodes
    exit 1
fi

echo ""

# Check observability namespace
echo -e "${YELLOW}Checking observability namespace...${NC}"

if ! kubectl get namespace monitoring &>/dev/null; then
    echo -e "${RED}✗ monitoring namespace not found${NC}"
    echo -e "${YELLOW}Run 'make setup' first${NC}"
    exit 1
fi

echo -e "${GREEN}✓ monitoring namespace exists${NC}"
echo ""

# Check observability pods
echo -e "${YELLOW}Checking observability pods...${NC}"

MONITORING_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)

if [ "$MONITORING_PODS" -lt 4 ]; then
    echo -e "${RED}✗ Not all observability pods are running${NC}"
    kubectl get pods -n monitoring
    exit 1
fi

echo -e "${GREEN}✓ Observability pods running${NC}"
echo ""

# Check Prometheus targets
echo -e "${YELLOW}Checking Prometheus targets...${NC}"

PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$PROMETHEUS_POD" ]; then
    echo -e "${RED}✗ Prometheus pod not found${NC}"
    exit 1
fi

# Check targets via port-forward (background)
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &>/dev/null &
PF_PID=$!
sleep 2

TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets | length' || echo 0)

kill $PF_PID 2>/dev/null || true

if [ "$TARGETS" -gt 0 ]; then
    echo -e "${GREEN}✓ Prometheus has $TARGETS active targets${NC}"
else
    echo -e "${YELLOW}⚠ Prometheus targets not yet available (may need more time)${NC}"
fi

echo ""

# Check key metrics
echo -e "${YELLOW}Checking key metrics...${NC}"

METRICS_FOUND=0

for metric in "container_memory_working_set_bytes" "container_spec_memory_limit_bytes" "kube_pod_container_status_restarts_total"; do
    if kubectl exec -n monitoring "$PROMETHEUS_POD" -- promtool query instant http://localhost:9090 "$metric" &>/dev/null 2>&1; then
        echo -e "${GREEN}✓ $metric found${NC}"
        METRICS_FOUND=$((METRICS_FOUND+1))
    fi
done

if [ "$METRICS_FOUND" -gt 0 ]; then
    echo -e "${GREEN}✓ Key metrics available${NC}"
else
    echo -e "${YELLOW}⚠ Metrics not yet available (may need more time)${NC}"
fi

echo ""

# Summary
echo -e "${GREEN}=== Verification Complete ===${NC}"
echo ""
echo -e "${YELLOW}Lab status:${NC}"
echo "  Kubernetes cluster: Ready"
echo "  Nodes: $READY_NODES/$TOTAL_NODES Ready"
echo "  Observability pods: Running"
echo "  Prometheus targets: $TARGETS"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Access Prometheus:"
echo "     kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "     Open http://localhost:9090"
echo ""
echo "  2. Access Grafana:"
echo "     kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "     Open http://localhost:3000 (admin/admin)"
echo ""
echo "  3. Run Episode 1:"
echo "     make demo-ep01"
echo ""
