#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"
SSH_DIR="$SCRIPT_DIR/ssh"

echo -e "${GREEN}=== K8s Under the Hood Lab Setup ===${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ terraform not found. Install with: brew install terraform${NC}"
    exit 1
fi

if ! command -v ansible &> /dev/null; then
    echo -e "${RED}✗ ansible not found. Install with: brew install ansible${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Install with: brew install kubectl${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq not found. Install with: brew install jq${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites found${NC}"
echo ""

# Check SSH keys
echo -e "${YELLOW}Checking SSH keys...${NC}"

if [ ! -f "$SSH_DIR/id_rsa" ]; then
    echo -e "${YELLOW}SSH keys not found. Generating...${NC}"
    mkdir -p "$SSH_DIR"
    ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/id_rsa" -N ""
    chmod 600 "$SSH_DIR/id_rsa"
    chmod 644 "$SSH_DIR/id_rsa.pub"
    echo -e "${GREEN}✓ SSH keys generated${NC}"
else
    echo -e "${GREEN}✓ SSH keys found${NC}"
fi

SSH_PUBLIC_KEY=$(cat "$SSH_DIR/id_rsa.pub")
echo ""

# Check Proxmox credentials
echo -e "${YELLOW}Checking Proxmox credentials...${NC}"

if [ -z "$PM_API_TOKEN_ID" ] || [ -z "$PM_API_TOKEN_SECRET" ]; then
    if [ -f ~/.proxmox-env ]; then
        echo -e "${YELLOW}Loading Proxmox credentials from ~/.proxmox-env${NC}"
        source ~/.proxmox-env
    else
        echo -e "${RED}✗ Proxmox API credentials not set${NC}"
        echo -e "${YELLOW}Set environment variables:${NC}"
        echo "  export PM_API_TOKEN_ID='root@pam!k8s-under-the-hood'"
        echo "  export PM_API_TOKEN_SECRET='your-token-secret'"
        echo -e "${YELLOW}Or create ~/.proxmox-env with the above${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Proxmox credentials found${NC}"
echo ""

# Terraform
echo -e "${YELLOW}Step 1: Provisioning VMs with Terraform...${NC}"
echo -e "${YELLOW}(First run downloads the Ubuntu 24.04 cloud image ~600MB to each${NC}"
echo -e "${YELLOW} target node: pve2/.87, pve3/.25, pve4/.47 — no VMs on pve/.48.${NC}"
echo -e "${YELLOW} Subsequent runs reuse the cached image.)${NC}"
cd "$TERRAFORM_DIR"

terraform init

terraform apply \
    -var "proxmox_api_token_id=$PM_API_TOKEN_ID" \
    -var "proxmox_api_token_secret=$PM_API_TOKEN_SECRET" \
    -var "ssh_public_key=$SSH_PUBLIC_KEY" \
    -auto-approve

echo -e "${GREEN}✓ VMs provisioned${NC}"
echo ""

# Wait for VMs to boot
echo -e "${YELLOW}Waiting for VMs to boot (2-3 minutes)...${NC}"
sleep 120

# Verify SSH connectivity
echo -e "${YELLOW}Verifying SSH connectivity...${NC}"

MASTER_IP=$(terraform output -raw master_ip)
WORKER1_IP=$(terraform output -raw worker1_ip)
WORKER2_IP=$(terraform output -raw worker2_ip)

for ip in "$MASTER_IP" "$WORKER1_IP" "$WORKER2_IP"; do
    echo -n "Checking $ip... "
    for i in {1..30}; do
        if ssh -i "$SSH_DIR/id_rsa" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$ip" "echo OK" &>/dev/null; then
            echo -e "${GREEN}✓${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}✗ Failed to connect${NC}"
            exit 1
        fi
        sleep 5
    done
done

echo -e "${GREEN}✓ All VMs are reachable${NC}"
echo ""

# Ansible
echo -e "${YELLOW}Step 2: Installing K3s with Ansible...${NC}"
cd "$ANSIBLE_DIR"

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml

# Run playbook
ansible-playbook -i inventory.ini k3s-cluster.yml

echo -e "${GREEN}✓ K3s cluster installed${NC}"
echo ""

# Copy kubeconfig
echo -e "${YELLOW}Step 3: Copying kubeconfig...${NC}"

KUBECONFIG_PATH=~/.kube/config-k8suth
mkdir -p ~/.kube

scp -i "$SSH_DIR/id_rsa" -o StrictHostKeyChecking=no ubuntu@"$MASTER_IP":~/.kube/config "$KUBECONFIG_PATH"

# Update server address in kubeconfig
sed -i '' "s/127.0.0.1/$MASTER_IP/g" "$KUBECONFIG_PATH"

echo -e "${GREEN}✓ kubeconfig copied to $KUBECONFIG_PATH${NC}"
echo ""

# Verify cluster
echo -e "${YELLOW}Step 4: Verifying Kubernetes cluster...${NC}"

export KUBECONFIG="$KUBECONFIG_PATH"

for i in {1..30}; do
    if kubectl get nodes &>/dev/null; then
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗ Failed to connect to Kubernetes API${NC}"
        exit 1
    fi
    sleep 5
done

kubectl get nodes

echo -e "${GREEN}✓ Kubernetes cluster verified${NC}"
echo ""

# Deploy observability stack
echo -e "${YELLOW}Step 5: Deploying observability stack...${NC}"

cd "$SCRIPT_DIR/observability"

kubectl apply -f namespace.yaml
kubectl apply -f prometheus.yaml
kubectl apply -f grafana.yaml
kubectl apply -f node-exporter.yaml
kubectl apply -f kube-state-metrics.yaml

echo -e "${GREEN}✓ Observability stack deployed${NC}"
echo ""

# Wait for observability pods
echo -e "${YELLOW}Waiting for observability pods to be ready...${NC}"

kubectl wait --for=condition=ready pod \
    -l app=prometheus \
    -n monitoring \
    --timeout=300s 2>/dev/null || true

kubectl wait --for=condition=ready pod \
    -l app=grafana \
    -n monitoring \
    --timeout=300s 2>/dev/null || true

echo -e "${GREEN}✓ Observability stack ready${NC}"
echo ""

# Summary
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${YELLOW}Cluster information:${NC}"
echo "  Master: $MASTER_IP"
echo "  Worker 1: $WORKER1_IP"
echo "  Worker 2: $WORKER2_IP"
echo ""
echo -e "${YELLOW}Access commands:${NC}"
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
echo "  kubectl get nodes"
echo ""
echo -e "${YELLOW}Observability:${NC}"
echo "  Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "  Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Verify the lab: make verify"
echo "  2. Run Episode 1: make demo-ep01"
echo ""
