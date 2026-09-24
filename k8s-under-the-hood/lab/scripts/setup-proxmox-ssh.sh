#!/bin/bash
set -e

# =============================================================================
# Setup SSH access from this controller to Proxmox nodes
# =============================================================================
# The bpg/proxmox Terraform provider requires SSH access to Proxmox nodes
# for cloud-init VM creation (disk creation, file downloads).
#
# It uses the SSH AGENT (not ~/.ssh/config), so keys must be:
#   1. Added to root@<proxmox-node>:~/.ssh/authorized_keys
#   2. Loaded in the local ssh-agent
#
# Run this script ONCE on each controller.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Proxmox node IPs (must match variables.tf target_nodes)
PROXMOX_NODES=("192.168.1.47" "192.168.1.87" "192.168.1.25")  # pve4, pve2, pve3
PROXMOX_MAIN="192.168.1.48"  # pve (main node, for API)

SSH_KEY="$HOME/.ssh/id_ed25519"

echo -e "${GREEN}=== Proxmox SSH Access Setup ===${NC}"
echo ""
echo "This script will:"
echo "  1. Generate an SSH key (if not present): $SSH_KEY"
echo "  2. Add the public key to root@ each Proxmox node"
echo "  3. Load the key into ssh-agent"
echo ""
echo "Proxmox nodes:"
echo "  pve4: 192.168.1.47"
echo "  pve2: 192.168.1.87"
echo "  pve3: 192.168.1.25"
echo "  pve:  192.168.1.48 (main, for cluster API)"
echo ""

# -------------------------------------------------------------------
# Step 1: Generate SSH key if not present
# -------------------------------------------------------------------
echo -e "${YELLOW}Step 1: Checking SSH key...${NC}"

if [ ! -f "$SSH_KEY" ]; then
    echo "Generating new SSH key: $SSH_KEY"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "homeops-controller"
    echo -e "${GREEN}✓ SSH key generated${NC}"
else
    echo -e "${GREEN}✓ SSH key found: $SSH_KEY${NC}"
fi

echo ""

# -------------------------------------------------------------------
# Step 2: Add public key to each Proxmox node
# -------------------------------------------------------------------
echo -e "${YELLOW}Step 2: Adding public key to Proxmox nodes...${NC}"
echo -e "${YELLOW}(You will be prompted for the root password on each node)${NC}"
echo ""

for node_ip in "${PROXMOX_NODES[@]}" "$PROXMOX_MAIN"; do
    echo -n "Adding key to root@$node_ip... "

    # Use ssh-copy-id if available, otherwise manual method
    if command -v ssh-copy-id &> /dev/null; then
        if ssh-copy-id -i "$SSH_KEY.pub" -o StrictHostKeyChecking=no "root@$node_ip" &>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗ Failed${NC}"
            echo -e "${YELLOW}  Try manually: ssh-copy-id -i $SSH_KEY.pub root@$node_ip${NC}"
        fi
    else
        # macOS may not have ssh-copy-id
        cat "$SSH_KEY.pub" | ssh -o StrictHostKeyChecking=no "root@$node_ip" \
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
            && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗ Failed${NC}"
    fi
done

echo ""

# -------------------------------------------------------------------
# Step 3: Verify SSH access (no password prompt)
# -------------------------------------------------------------------
echo -e "${YELLOW}Step 3: Verifying passwordless SSH access...${NC}"

ALL_OK=true
for node_ip in "${PROXMOX_NODES[@]}" "$PROXMOX_MAIN"; do
    echo -n "Testing root@$node_ip... "
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o PasswordAuthentication=no -o BatchMode=yes "root@$node_ip" "echo OK" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Failed (password still required)${NC}"
        ALL_OK=false
    fi
done

echo ""

# -------------------------------------------------------------------
# Step 4: Load key into ssh-agent
# -------------------------------------------------------------------
echo -e "${YELLOW}Step 4: Loading key into ssh-agent...${NC}"

# Start ssh-agent if not running (macOS: use launchd; Linux: eval)
if [ "$(uname)" = "Darwin" ]; then
    # macOS
    ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || ssh-add "$SSH_KEY"
else
    # Linux
    eval "$(ssh-agent -s)" 2>/dev/null || true
    ssh-add "$SSH_KEY"
fi

echo ""
echo -e "${YELLOW}Keys currently in agent:${NC}"
ssh-add -L || echo "  (no keys in agent - this is a problem!)"

echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""

if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}✓ SSH access configured to all Proxmox nodes${NC}"
    echo ""
    echo "The Terraform Proxmox provider can now SSH to nodes."
    echo ""
    echo "Next steps:"
    echo "  1. cd lab/terraform"
    echo "  2. source ~/.proxmox-env"
    echo "  3. terraform init"
    echo "  4. terraform apply"
else
    echo -e "${RED}✗ Some nodes failed SSH setup${NC}"
    echo ""
    echo "To fix manually, run on each failed node:"
    echo "  ssh-copy-id -i $SSH_KEY.pub root@<node-ip>"
    echo ""
    echo "Then verify:"
    echo "  ssh -i $SSH_KEY root@<node-ip> 'echo OK'"
fi

echo ""
echo -e "${YELLOW}IMPORTANT (macOS):${NC}"
echo "To make the key persist across reboots, add to ~/.ssh/config:"
echo ""
echo "  Host *"
echo "    AddKeysToAgent yes"
echo "    UseKeychain yes"
echo "    IdentityFile $SSH_KEY"
