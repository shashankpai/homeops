# Prerequisites

## Required Tools on Mac

### 1. Terraform (v1.5+)

```bash
# Install via Homebrew
brew install terraform

# Verify
terraform version
```

### 2. Ansible (v2.10+)

```bash
# Install via Homebrew or pip
brew install ansible
# OR
pip3 install ansible

# Verify
ansible --version
```

### 3. kubectl (v1.36+)

```bash
# Install via Homebrew
brew install kubectl

# Verify
kubectl version --client
```

### 4. jq (JSON processor)

```bash
# Install via Homebrew
brew install jq

# Verify
jq --version
```

### 5. SSH keys

The lab uses SSH keys to access VMs. You can either:

**Option A: Use existing keys**
```bash
# Copy your existing SSH keys to the lab directory
cp ~/.ssh/id_rsa lab/ssh/id_rsa
cp ~/.ssh/id_rsa.pub lab/ssh/id_rsa.pub
chmod 600 lab/ssh/id_rsa
```

**Option B: Generate new keys**
```bash
mkdir -p lab/ssh
ssh-keygen -t rsa -b 4096 -f lab/ssh/id_rsa -N ""
```

### 6. Proxmox API Token

You need a Proxmox API token to provision VMs.

**Important**: Your 4 Proxmox nodes (pve/.48, pve2/.87, pve3/.25, pve4/.47) form a single cluster with ONE shared permission database. You only need to create the token **once** — it works for all nodes. You do NOT need per-host tokens.

**Option A: Create via CLI (recommended)**

```bash
# SSH to any node in the cluster (e.g. the main one):
ssh root@192.168.1.48

# Create the token (privsep 0 = full root permissions, fine for a lab):
pveum user token add root@pam k8s-under-the-hood --privsep 0

# Output:
# ┌────────────┬──────────┐
# │ token-name │ value    │
# ╞════════════╪══════════╡
# │ k8s-under-the-hood │ <secret> │
# └────────────┴──────────┘
#
# Copy the secret value NOW — it is shown only once!
```

**Option B: Create via Web UI**

1. Log in to Proxmox web UI: `https://192.168.1.48:8006` (any node works)
2. Go to **Datacenter → Permissions → API Tokens**
3. Click **Add**
4. Set:
   - User: `root@pam`
   - Token ID: `k8s-under-the-hood`
   - Privilege Separation: unchecked
5. Click **Add**
6. Copy the token secret (you'll only see it once)

Then set environment variables:

```bash
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="your-token-secret-here"
```

Or create `~/.proxmox-env`:
```bash
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="your-token-secret-here"
```

Then source it before running setup:
```bash
source ~/.proxmox-env
```

> The Terraform endpoint stays `https://192.168.1.48:8006` — any node's API
> endpoint serves the whole cluster. Terraform's `node_name` setting on each
> VM decides which node the VM actually lands on.

### 7. One-Time SSH Access to Proxmox Nodes (Template Bootstrap)

The Proxmox API has no endpoint for importing a disk image into a VM — the
Terraform provider must SSH into the node to do it. To keep day-to-day
operations SSH-free, the lab uses **per-node templates + API-only clones**:

- **One-time bootstrap** (`make templates` or the first `make setup`) creates an
  Ubuntu template on each node — this step needs SSH to the nodes
- **All subsequent operations** (VM creation, destroy, rebuild) are pure API
  clones — any controller with just the API token can run them

Set up the one-time SSH access:

```bash
# 1. Authorize your key on each target node
ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.47  # pve4
ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.87  # pve2
ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.25  # pve3

# 2. Load the key into ssh-agent (IMPORTANT: the provider reads the
#    ssh-agent ONLY — it does not use ~/.ssh/config)
ssh-add lab/ssh/id_rsa

# 3. Verify (should print your key with no password prompt)
ssh-add -L
```

> **Why ssh-agent?** The bpg/proxmox provider authorizes node SSH sessions via
> the agent of the user running Terraform. A key sitting in `~/.ssh/config`
> is invisible to it.

---

## Proxmox Requirements

### Ubuntu Templates (per-node) + API-Only Clones

The lab uses one Ubuntu 24.04 template per target node (local-lvm is not
shared storage, so each node needs its own). The flow:

```
One-time bootstrap (SSH to nodes required, run from ONE controller):
  download Ubuntu 24.04 cloud image (~600MB) to each node (API)
  → import image as template disk on each node (SSH)
  → templates exist as VM IDs 9100-9102

Every subsequent operation (API-only, any controller):
  clone template on the target node → apply cloud-init → boot
```

- Templates: `ubuntu-2404-pve2` (9100), `ubuntu-2404-pve3` (9101), `ubuntu-2404-pve4` (9102)
- Lab VMs are full clones of the node-local template
- Cloning is a first-class Proxmox API operation — **no SSH required**
- Ubuntu cloud images have cloud-init built in, so SSH keys and static IPs
  are injected automatically on first boot

**No VMs are created on pve (.48)** — the main node stays free of lab VMs.

**Requirements this satisfies automatically:**
- Ubuntu 24.04 LTS with cloud-init built in
- QEMU guest agent is installed by the Ansible playbook
- SSH server included in the cloud image

### VM Placement and Sizing

| VM | Proxmox node | Host RAM | vCPU | RAM | Disk | IP |
|----|--------------|----------|------|-----|------|----|
| k8suth-master | pve4 (.47) | 16GB | 2 | 6GB | 30GB | 192.168.1.81 |
| k8suth-worker1 | pve2 (.87) | 8GB | 2 | 4GB | 30GB | 192.168.1.82 |
| k8suth-worker2 | pve3 (.25) | 8GB | 2 | 4GB | 30GB | 192.168.1.83 |

Each host runs exactly one lab VM, leaving ~1.5GB+ for the Proxmox host OS itself.

### Network Bridge

The lab uses the default Proxmox bridge `vmbr0`. Verify it exists:

```bash
# SSH to Proxmox host
ssh root@192.168.1.48

# List bridges
ip link show | grep vmbr0

# Expected output:
# 2: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
```

### IP Range

The lab uses static IPs in the range `192.168.1.81-83`. Verify these IPs are:

1. **Not in use** on your network
2. **Not in the DHCP pool** of your router (typically 192.168.1.100-254)

Check your router's DHCP settings to confirm the pool range.

---

## Storage Requirements

### Proxmox Nodes (pve2/.87, pve3/.25, pve4/.47)

The lab VMs are distributed across three nodes (NOT on pve/.48):

- **Disk space**: ~35GB per node (30GB VM disk + ~600MB cloud image cache)
- **RAM**: 6GB on pve4 (master), 4GB on pve2/pve3 (workers) — leaves host OS headroom

Verify available resources per node:

```bash
# SSH to each target node
ssh root@192.168.1.47   # pve4 — hosts master
ssh root@192.168.1.87   # pve2 — hosts worker1
ssh root@192.168.1.25   # pve3 — hosts worker2

# On each node:
pvesh get /nodes/{node}/storage   # disk space
free -h                           # RAM
pvecm nodes                       # cluster membership
```

### Local Machine (Mac)

- **Disk space**: ~5GB for Terraform state, kubeconfig, and scripts
- **RAM**: ~4GB available for running kubectl, port-forwarding, etc.

---

## Network Requirements

### Connectivity

Your Mac must be able to reach:

1. **Proxmox API**: `https://192.168.1.48:8006`
2. **VMs**: `192.168.1.81-83` (via SSH)
3. **Kubernetes API**: `192.168.1.81:6443` (via kubectl)

Test connectivity:

```bash
# Test Proxmox API
curl -k https://192.168.1.48:8006/api2/json/version

# Test VM IPs (after setup)
ping 192.168.1.81
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "echo OK"
```

### DNS

The VMs need internet access to:

1. Download K3s binary
2. Pull container images (Prometheus, Grafana, etc.)
3. Install packages via apt

Verify DNS resolution on VMs:

```bash
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "nslookup google.com"
```

---

## Verification Checklist

Before running `make setup`, verify:

- [ ] Terraform installed: `terraform version`
- [ ] Ansible installed: `ansible --version`
- [ ] kubectl installed: `kubectl version --client`
- [ ] jq installed: `jq --version`
- [ ] SSH keys exist: `ls -la lab/ssh/id_rsa`
- [ ] Proxmox API token set: `echo $PM_API_TOKEN_ID`
- [ ] Cluster nodes reachable: `pvecm nodes` (from any node)
- [ ] Network bridge vmbr0 exists on target nodes: `ip link show | grep vmbr0`
- [ ] IPs 192.168.1.81-83 are free: `ping 192.168.1.81` (should fail)
- [ ] pve4 has 35GB+ disk and 8GB+ free RAM: `pvesh get /nodes/pve4/storage`
- [ ] pve2/pve3 each have 35GB+ disk and 6GB+ free RAM
- [ ] Mac can reach Proxmox API: `curl -k https://192.168.1.48:8006/api2/json/version`

---

## Troubleshooting

### Terraform fails to authenticate

**Error**: `Error: Failed to authenticate`

**Solution**: Verify Proxmox API token:
```bash
echo $PM_API_TOKEN_ID
echo $PM_API_TOKEN_SECRET
```

If not set, source `~/.proxmox-env`:
```bash
source ~/.proxmox-env
terraform init
```

### Template bootstrap SSH authentication fails

**Error**:
```
Error: creating custom disk: unable to authenticate user "" over SSH to "192.168.1.47:22".
Please verify that ssh-agent is correctly loaded with an authorized key via 'ssh-add -L'
attempted methods [none password], no supported methods remain
```

**Cause**: The one-time template bootstrap (image-to-disk import) runs on the
Proxmox node itself, and the provider authenticates via **ssh-agent only**
(it ignores `~/.ssh/config`).

**Solution**:
```bash
# 1. Authorize your key on each target node
ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.47
ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.87
ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.25

# 2. Load it in the agent
ssh-add lab/ssh/id_rsa

# 3. Verify the agent sees it
ssh-add -L
```

This is needed **only for the bootstrap** (`make templates`). Once templates
exist, VM operations are API-only clones and need no SSH.

### Ubuntu cloud image download fails

**Error**: `Error: failed to download file` or timeout during `terraform apply`

**Solution**: The download (~600MB per node) needs internet access from each
target node (pve2, pve3, pve4). Verify:
```bash
# From each target node:
curl -sI https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img | head -1
```

If a node can't reach the URL, check its DNS/gateway settings. The image is
cached on the node's `local` storage — re-running setup reuses it. To force a
re-download, delete the cached file first:
```bash
pvesh delete /nodes/{node}/storage/local/file-content/ubuntu-24.04-noble-server-cloudimg-amd64.img
```

### VM creation fails on a node

**Error**: `Error: VM creation failed` or `no space left on device`

**Solution**: Check the target node's resources:
```bash
pvesh get /nodes/{node}/storage   # local-lvm free space
free -h                           # available RAM
```

If a node is too full, change the VM placement in `lab/terraform/variables.tf`
(`vm_nodes` map) and re-run setup.

### IPs already in use

**Error**: `Error: IP 192.168.1.81 already in use`

**Solution**: Change the IP range in `lab/terraform/variables.tf`:
```hcl
variable "vm_ips" {
  default = ["192.168.1.91", "192.168.1.92", "192.168.1.93"]
}
```

Then update the plan file and all references.

### Ansible fails to connect

**Error**: `UNREACHABLE! => {"msg": "Failed to connect to the host via ssh"`

**Solution**: Verify SSH connectivity:
```bash
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "echo OK"
```

If it fails, check:
1. VMs are running: `qm list | grep k8suth`
2. VMs have IP addresses: `qm guest cmd <vmid> network-get-interfaces`
3. SSH keys are correct: `ls -la lab/ssh/id_rsa`

### Kubernetes nodes not ready

**Error**: `kubectl get nodes` shows nodes as NotReady

**Solution**: Wait a few minutes for K3s to fully initialize:
```bash
kubectl get nodes -w
```

If still not ready after 5 minutes, check logs:
```bash
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "sudo journalctl -u k3s -f"
```

---

## Next Steps

Once all prerequisites are verified, run:

```bash
make setup
```

This will provision the lab and install all components.
