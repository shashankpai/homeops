#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

echo -e "${RED}=== K8s Under the Hood Lab Teardown ===${NC}"
echo ""
echo -e "${RED}WARNING: This will destroy all VMs and delete Terraform state${NC}"
echo ""

# Confirm
read -p "Are you sure you want to destroy the lab? Type 'yes' to confirm: " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Destroying VMs...${NC}"

cd "$TERRAFORM_DIR"

# Check Proxmox credentials
if [ -z "$PM_API_TOKEN_ID" ] || [ -z "$PM_API_TOKEN_SECRET" ]; then
    if [ -f ~/.proxmox-env ]; then
        source ~/.proxmox-env
    else
        echo -e "${RED}✗ Proxmox API credentials not set${NC}"
        exit 1
    fi
fi

terraform destroy \
    -var "proxmox_api_token_id=$PM_API_TOKEN_ID" \
    -var "proxmox_api_token_secret=$PM_API_TOKEN_SECRET" \
    -var "ssh_public_key=$(cat $SCRIPT_DIR/ssh/id_rsa.pub)" \
    -auto-approve

echo -e "${GREEN}✓ VMs destroyed${NC}"
echo ""

# Clean up kubeconfig
echo -e "${YELLOW}Cleaning up kubeconfig...${NC}"

if [ -f ~/.kube/config-k8suth ]; then
    rm ~/.kube/config-k8suth
    echo -e "${GREEN}✓ kubeconfig removed${NC}"
fi

echo ""
echo -e "${GREEN}=== Teardown Complete ===${NC}"
echo ""
echo -e "${YELLOW}Lab has been destroyed. To set up again:${NC}"
echo "  make setup"
echo ""
