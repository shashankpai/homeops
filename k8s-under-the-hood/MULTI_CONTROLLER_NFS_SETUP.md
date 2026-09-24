# Multi-Controller Setup with Local NFS (No Terraform Cloud or S3)

Execute the K8s Under the Hood lab from any control machine (Mac, Linux servers) using a shared NFS mount for Terraform state and kubeconfig.

---

## Overview

This guide enables you to:

1. **Execute from any controller** — Mac, Linux servers, or any machine with Terraform/Ansible/kubectl
2. **Share Terraform state via NFS** — Centralized state without cloud services
3. **Access from anywhere** — kubeconfig and SSH keys on shared NFS
4. **Maintain consistency** — Single source of truth for infrastructure

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Control Machines                    │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────┐               │
│  │  Mac (primary)   │  │  Linux server 1  │               │
│  │  /Users/...      │  │  /home/user/...  │               │
│  └────────┬─────────┘  └────────┬─────────┘               │
│           │                     │                          │
│           └─────────────────────┘                          │
│                     │                                      │
│                     ↓                                      │
│         ┌───────────────────────┐                         │
│         │   Git Repository      │                         │
│         │   (homeops on GitHub) │                         │
│         └───────────┬───────────┘                         │
│                     │                                      │
│         ┌───────────┴───────────┐                         │
│         ↓                       ↓                          │
│   ┌──────────────┐      ┌──────────────┐                 │
│   │  NFS Mount   │      │  NFS Mount   │                 │
│   │  Terraform   │      │  Terraform   │                 │
│   │  State       │      │  State       │                 │
│   └──────────────┘      └──────────────┘                 │
│         │                       │                         │
│         └───────────┬───────────┘                         │
│                     ↓                                      │
│         ┌───────────────────────┐                         │
│         │   NFS Server          │                         │
│         │   (Proxmox Host or    │                         │
│         │    Dedicated NAS)      │                         │
│         └───────────┬───────────┘                         │
│                     ↓                                      │
│         ┌───────────────────────┐                         │
│         │   Proxmox Cluster     │                         │
│         │   (192.168.1.48)      │                         │
│         └───────────────────────┘                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### All Controllers Need

1. **Git**
   ```bash
   git --version  # v2.0+
   ```

2. **Terraform**
   ```bash
   terraform version  # v1.5+
   ```

3. **Ansible**
   ```bash
   ansible --version  # v2.10+
   ```

4. **kubectl**
   ```bash
   kubectl version --client  # v1.36+
   ```

5. **jq**
   ```bash
   jq --version
   ```

6. **NFS Client Tools**
   
   **macOS** (built-in, no installation needed)
   ```bash
   mount_nfs -h  # Should work
   ```
   
   **Ubuntu/Debian**
   ```bash
   sudo apt-get install -y nfs-common
   ```
   
   **RHEL/CentOS**
   ```bash
   sudo yum install -y nfs-utils
   ```

### NFS Server Setup

You need an NFS server to host the shared state. Options:

**Option A: Use Your Proxmox Host (192.168.1.48)**

If your Proxmox host has spare storage and can run NFS:

```bash
# SSH to Proxmox host
ssh root@192.168.1.48

# Create NFS export directory
mkdir -p /export/k8s-terraform-state
mkdir -p /export/k8s-kubeconfig

# Set permissions
chmod 755 /export/k8s-terraform-state
chmod 755 /export/k8s-kubeconfig

# Edit /etc/exports
cat >> /etc/exports << 'EOF'
/export/k8s-terraform-state 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/k8s-kubeconfig 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

# Apply exports
exportfs -a

# Verify
showmount -e localhost
```

**Option B: Use a Dedicated NAS**

If you have a NAS (Synology, QNAP, etc.), create NFS shares:
- `/k8s-terraform-state` — for Terraform state
- `/k8s-kubeconfig` — for kubeconfig and SSH keys

**Option C: Use a Linux Server**

If you have a Linux server in your homelab:

```bash
# Install NFS server
sudo apt-get install -y nfs-kernel-server

# Create export directories
sudo mkdir -p /export/k8s-terraform-state
sudo mkdir -p /export/k8s-kubeconfig

# Set permissions
sudo chmod 755 /export/k8s-terraform-state
sudo chmod 755 /export/k8s-kubeconfig

# Edit /etc/exports
sudo bash -c 'cat >> /etc/exports << EOF
/export/k8s-terraform-state 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/k8s-kubeconfig 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF'

# Apply exports
sudo exportfs -a

# Start NFS service
sudo systemctl restart nfs-kernel-server

# Verify
showmount -e localhost
```

---

## Setup Steps

### Step 1: Clone the Repository on Each Controller

```bash
# On each control machine
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood
```

### Step 2: Create Proxmox API Token (One-Time, Any Controller)

Create the token once on your Proxmox cluster:

```bash
ssh root@192.168.1.48
pveum user token add root@pam k8s-under-the-hood --privsep 0
# Copy the secret shown
```

### Step 3: Mount NFS on Each Controller

**macOS**

```bash
# Create mount points
mkdir -p ~/nfs/k8s-terraform-state
mkdir -p ~/nfs/k8s-kubeconfig

# Mount NFS (replace 192.168.1.48 with your NFS server IP)
sudo mount_nfs -o resvport 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state
sudo mount_nfs -o resvport 192.168.1.48:/export/k8s-kubeconfig ~/nfs/k8s-kubeconfig

# Verify mounts
mount | grep nfs

# Make mounts persistent (add to /etc/fstab or use automount)
# For now, you'll need to remount after reboot
```

**Ubuntu/Debian**

```bash
# Create mount points
mkdir -p ~/nfs/k8s-terraform-state
mkdir -p ~/nfs/k8s-kubeconfig

# Mount NFS
sudo mount -t nfs -o vers=3 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state
sudo mount -t nfs -o vers=3 192.168.1.48:/export/k8s-kubeconfig ~/nfs/k8s-kubeconfig

# Verify mounts
mount | grep nfs

# Make mounts persistent (add to /etc/fstab)
echo "192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state nfs vers=3,defaults 0 0" | sudo tee -a /etc/fstab
echo "192.168.1.48:/export/k8s-kubeconfig ~/nfs/k8s-kubeconfig nfs vers=3,defaults 0 0" | sudo tee -a /etc/fstab
```

### Step 4: Create Terraform Backend Configuration

On **each controller**, create `lab/terraform/backend.tf`:

```hcl
terraform {
  backend "local" {
    path = "~/nfs/k8s-terraform-state/terraform.tfstate"
  }
}
```

**Important**: The path must be the same on all controllers (e.g., `~/nfs/k8s-terraform-state/`).

### Step 5: Set Up Environment Variables

On **each controller**, create `~/.proxmox-env`:

```bash
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<secret-from-step-2>"
EOF

chmod 600 ~/.proxmox-env
```

### Step 6: Initialize Terraform Backend

On **one controller only** (the first time):

```bash
cd /path/to/homeops/k8s-under-the-hood/lab/terraform
source ~/.proxmox-env
terraform init
```

On **subsequent controllers**, just run:
```bash
cd /path/to/homeops/k8s-under-the-hood/lab/terraform
terraform init
# Terraform will detect the shared state file
```

---

## Execution from Any Controller

### Bring Up the Lab

```bash
# On the primary controller (Mac)
cd /path/to/homeops/k8s-under-the-hood
source ~/.proxmox-env
make setup
```

### Verify the Lab

```bash
# On any controller
make verify
```

### Access from Any Controller

```bash
# Set kubeconfig (from shared NFS)
export KUBECONFIG=~/nfs/k8s-kubeconfig/config-k8suth

# Check cluster
kubectl get nodes

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

### Destroy the Lab

```bash
make teardown
```

---

## Workflow Example: Multi-Controller Setup with NFS

### Controller 1: Mac (Primary)

```bash
# Clone repo
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood

# Mount NFS
mkdir -p ~/nfs/k8s-terraform-state
mkdir -p ~/nfs/k8s-kubeconfig
sudo mount_nfs -o resvport 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state
sudo mount_nfs -o resvport 192.168.1.48:/export/k8s-kubeconfig ~/nfs/k8s-kubeconfig

# Create backend.tf
cat > lab/terraform/backend.tf << 'EOF'
terraform {
  backend "local" {
    path = "~/nfs/k8s-terraform-state/terraform.tfstate"
  }
}
EOF

# Initialize and bring up lab
source ~/.proxmox-env
cd lab/terraform
terraform init
cd ../..
make setup

# kubeconfig is automatically copied to ~/nfs/k8s-kubeconfig/
```

### Controller 2: Linux Server

```bash
# Clone repo
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood

# Mount NFS
mkdir -p ~/nfs/k8s-terraform-state
mkdir -p ~/nfs/k8s-kubeconfig
sudo mount -t nfs -o vers=3 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state
sudo mount -t nfs -o vers=3 192.168.1.48:/export/k8s-kubeconfig ~/nfs/k8s-kubeconfig

# Create backend.tf (same as Mac)
cat > lab/terraform/backend.tf << 'EOF'
terraform {
  backend "local" {
    path = "~/nfs/k8s-terraform-state/terraform.tfstate"
  }
}
EOF

# Initialize (detects shared state)
source ~/.proxmox-env
cd lab/terraform
terraform init

# Access the cluster
export KUBECONFIG=~/nfs/k8s-kubeconfig/config-k8suth
kubectl get nodes
```

---

## Best Practices

### 1. State Management

✅ **DO**
- Store state on NFS with proper permissions
- Use file locking (Terraform handles this)
- Backup NFS regularly
- Monitor NFS mount status

❌ **DON'T**
- Commit terraform.tfstate to git
- Use local state across multiple controllers
- Modify state files directly

### 2. Credentials

✅ **DO**
- Store API tokens in environment variables
- Use `~/.proxmox-env` with `chmod 600`
- Rotate tokens periodically
- Keep ~/.proxmox-env out of git

❌ **DON'T**
- Hardcode tokens in Terraform files
- Commit `.env` files to git
- Share tokens via Slack/email

### 3. NFS Access Control

✅ **DO**
- Restrict NFS exports to your network (192.168.1.0/24)
- Use `no_root_squash` only if necessary
- Monitor NFS access logs
- Backup NFS exports regularly

❌ **DON'T**
- Export NFS to the entire internet
- Use weak NFS permissions
- Store unencrypted secrets on NFS

### 4. Coordination

✅ **DO**
- Designate one controller as "primary" for setup
- Document who's running what and when
- Wait for Terraform to finish before running from another controller
- Communicate state changes to the team

❌ **DON'T**
- Run `terraform apply` from multiple controllers simultaneously
- Modify state files directly
- Assume another controller isn't making changes

---

## Troubleshooting

### "Permission denied" when mounting NFS

**Cause**: NFS export permissions or firewall.

**Solution**:
```bash
# Verify NFS server is exporting
showmount -e 192.168.1.48

# Check firewall on NFS server
sudo ufw allow from 192.168.1.0/24 to any port 111
sudo ufw allow from 192.168.1.0/24 to any port 2049

# Try mounting with verbose output
sudo mount -v -t nfs -o vers=3 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state
```

### "Stale NFS file handle"

**Cause**: NFS server went down or network issue.

**Solution**:
```bash
# Unmount and remount
sudo umount ~/nfs/k8s-terraform-state
sudo mount -t nfs -o vers=3 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state

# Or restart NFS server
ssh root@192.168.1.48 "systemctl restart nfs-kernel-server"
```

### "Error: Error acquiring the state lock"

**Cause**: Another controller is running Terraform or lock file is stuck.

**Solution**:
```bash
# Wait for other controller to finish
# Or check lock file
ls -la ~/nfs/k8s-terraform-state/.terraform.lock.hcl

# If stuck, remove lock (use with caution)
rm ~/nfs/k8s-terraform-state/.terraform.lock.hcl
```

### "kubeconfig not found"

**Cause**: kubeconfig not copied to NFS.

**Solution**:
```bash
# Check if kubeconfig exists on NFS
ls -la ~/nfs/k8s-kubeconfig/

# If not, copy from primary controller
scp user@primary-controller:~/.kube/config-k8suth ~/nfs/k8s-kubeconfig/config-k8suth
```

### "NFS mount not persisting after reboot"

**Cause**: Mount not added to /etc/fstab.

**Solution**:
```bash
# Add to /etc/fstab (Linux)
echo "192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state nfs vers=3,defaults 0 0" | sudo tee -a /etc/fstab

# Or use automount (macOS)
# Create /etc/auto_nfs with:
# k8s-terraform-state -o resvport 192.168.1.48:/export/k8s-terraform-state
# k8s-kubeconfig -o resvport 192.168.1.48:/export/k8s-kubeconfig

# Then enable automount
sudo automount -vc
```

---

## Recommended Setup

For your use case (Mac + Linux servers, no Terraform Cloud/S3):

### 1. **NFS Server**: Proxmox Host (192.168.1.48)
- ✅ Already running
- ✅ Accessible from all controllers
- ✅ No additional infrastructure

### 2. **Shared Directories**
- `/export/k8s-terraform-state` — Terraform state
- `/export/k8s-kubeconfig` — kubeconfig and SSH keys

### 3. **Mount Points on Controllers**
- `~/nfs/k8s-terraform-state` — Mac and Linux
- `~/nfs/k8s-kubeconfig` — Mac and Linux

### 4. **Credentials**: Environment Variables
- `~/.proxmox-env` — Proxmox API token (not in git)

### 5. **Coordination**: Primary Controller
- Mac runs `make setup`
- Linux servers run `make verify` and access

---

## Quick Setup (10 Minutes)

### On Proxmox Host (192.168.1.48)

```bash
ssh root@192.168.1.48

# Create NFS exports
mkdir -p /export/k8s-terraform-state
mkdir -p /export/k8s-kubeconfig
chmod 755 /export/k8s-terraform-state
chmod 755 /export/k8s-kubeconfig

# Add to /etc/exports
cat >> /etc/exports << 'EOF'
/export/k8s-terraform-state 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/k8s-kubeconfig 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

# Apply exports
exportfs -a

# Verify
showmount -e localhost
```

### On Each Controller

```bash
# Clone repo
git clone https://github.com/yourusername/homeops.git
cd homeops/k8s-under-the-hood

# Mount NFS
mkdir -p ~/nfs/k8s-terraform-state
mkdir -p ~/nfs/k8s-kubeconfig

# macOS
sudo mount_nfs -o resvport 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state
sudo mount_nfs -o resvport 192.168.1.48:/export/k8s-kubeconfig ~/nfs/k8s-kubeconfig

# Linux
# sudo mount -t nfs -o vers=3 192.168.1.48:/export/k8s-terraform-state ~/nfs/k8s-terraform-state
# sudo mount -t nfs -o vers=3 192.168.1.48:/export/k8s-kubeconfig ~/nfs/k8s-kubeconfig

# Create backend.tf
cat > lab/terraform/backend.tf << 'EOF'
terraform {
  backend "local" {
    path = "~/nfs/k8s-terraform-state/terraform.tfstate"
  }
}
EOF

# Set credentials
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<your-secret>"
EOF
chmod 600 ~/.proxmox-env

# Initialize Terraform
source ~/.proxmox-env
cd lab/terraform
terraform init
cd ../..
```

### On Primary Controller Only

```bash
# Bring up the lab
make setup

# kubeconfig is automatically copied to ~/nfs/k8s-kubeconfig/
```

### On Other Controllers

```bash
# Access the lab
export KUBECONFIG=~/nfs/k8s-kubeconfig/config-k8suth
kubectl get nodes
```

---

## Summary

| Aspect | Solution |
|--------|----------|
| **State Backend** | Local NFS mount (~/nfs/k8s-terraform-state/) |
| **NFS Server** | Proxmox host (192.168.1.48) or dedicated NAS |
| **Credentials** | Environment variables (~/.proxmox-env) |
| **kubeconfig** | Shared NFS mount (~/nfs/k8s-kubeconfig/) |
| **SSH Keys** | Shared NFS mount (~/nfs/k8s-kubeconfig/) |
| **Coordination** | Designate primary controller (Mac) |
| **Execution** | Any controller can run make setup |
| **Access** | All controllers can access the lab |

This setup enables you to execute the lab from any controller while maintaining a single source of truth for infrastructure state, all without requiring Terraform Cloud or S3.
