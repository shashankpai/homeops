# Phase 1 Setup — Complete Command Reference

## Overview

This document provides the exact commands to get Phase 1 up and running, plus what gets provisioned.

---

## Prerequisites Check (5 minutes)

Before running setup, verify all required tools are installed:

```bash
# Check Terraform
terraform version
# Expected: Terraform v1.5+

# Check Ansible
ansible --version
# Expected: ansible [core 2.10+]

# Check kubectl
kubectl version --client
# Expected: Client Version: v1.36+

# Check jq
jq --version
# Expected: jq-1.6+

# Check SSH keys exist
ls -la ~/.ssh/id_rsa
# If not found, generate: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

If any tools are missing, see `docs/prerequisites.md` for installation instructions.

---

## Step 1: Navigate to the Lab Directory

```bash
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood
```

---

## Step 2: Set Proxmox API Credentials

You need a Proxmox API token. If you don't have one, create it first on your Proxmox host.

### Option A: Set Environment Variables (Session-only)

```bash
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="your-actual-token-secret-here"
```

### Option B: Create ~/.proxmox-env (Persistent)

```bash
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="your-actual-token-secret-here"
EOF

chmod 600 ~/.proxmox-env

# Then source it before running setup
source ~/.proxmox-env
```

### How to Create a Proxmox API Token

If you don't h RRave a token yet:

1. SSH to your Proxmox host:
   ```bash
   ssh root@192.168.1.48
   ```

2. Create the token:
   ```bash
   pveum user token add root@pam k8s-under-the-hood --privsep 0
   ```

3. Copy the token secret (shown once)

4. Set the environment variables with the token ID and secret

> **Note**: One token covers your whole cluster. Proxmox clusters share a
> single permission database, so a token created at the Datacenter level
> (like above) manages ALL nodes — pve/.48, pve2/.87, pve3/.25, and
> pve4/.47. You do NOT need separate tokens per host. The API endpoint
> (192.168.1.48:8006) serves the entire cluster; Terraform's `node_name`
> per VM decides where each VM actually runs.

---

## Step 3: Run the Setup (15-20 minutes)

```bash
make setup
```

This single command will:

1. **Check prerequisites** — Verify terraform, ansible, kubectl, jq are installed
2. **Generate SSH keys** — If not already present in `lab/ssh/`
3. **Verify Proxmox credentials** — Check API token is valid
4. **Run Terraform** — Provision 3 VMs on Proxmox (VMs are full clones of the per-node templates created by the one-time `make templates` bootstrap)
5. **Wait for VMs** — Allow 2-3 minutes for VMs to boot
6. **Verify SSH connectivity** — Ensure all VMs are reachable
7. **Run Ansible** — Install K3s on all VMs
8. **Copy kubeconfig** — Download kubeconfig to `~/.kube/config-k8suth`
9. **Deploy observability** — Install Prometheus, Grafana, node-exporter, kube-state-metrics
10. **Wait for pods** — Ensure all observability pods are running
11. **Print summary** — Show cluster info and next steps

### What Happens During Setup

```
make setup
  │
  ├─ Check prerequisites (terraform, ansible, kubectl, jq)
  │
  ├─ Generate SSH keys (if needed)
  │  └─ lab/ssh/id_rsa, lab/ssh/id_rsa.pub
  │
  ├─ Verify Proxmox credentials
  │
  ├─ Run terraform apply
  │  ├─ Download Ubuntu 24.04 cloud image to pve2, pve3, pve4
  │  │  └─ ~600MB per node, cached for re-runs (first run only)
  │  ├─ Create master VM (192.168.1.81) on pve4/.47
  │  │  └─ 2 vCPU, 6GB RAM, 30GB disk
  │  ├─ Create worker1 VM (192.168.1.82) on pve2/.87
  │  │  └─ 2 vCPU, 4GB RAM, 30GB disk
  │  ├─ Create worker2 VM (192.168.1.83) on pve3/.25
  │  │  └─ 2 vCPU, 4GB RAM, 30GB disk
  │  ├─ NO VMs on pve/.48 (main node stays free)
  │  └─ Generate Ansible inventory
  │
  ├─ Wait 2 minutes for VMs to boot
  │
  ├─ Verify SSH connectivity to all VMs
  │
  ├─ Run Ansible playbook
  │  ├─ Install K3s v1.36.3+k3s1 on master
  │  ├─ Install K3s v1.36.3+k3s1 on workers
  │  ├─ Wait for all nodes to be Ready
  │  └─ Copy kubeconfig to ubuntu user
  │
  ├─ Copy kubeconfig to Mac
  │  └─ ~/.kube/config-k8suth
  │
  ├─ Deploy observability stack
  │  ├─ Create monitoring namespace
  │  ├─ Deploy Prometheus
  │  ├─ Deploy Grafana
  │  ├─ Deploy node-exporter (DaemonSet)
  │  └─ Deploy kube-state-metrics
  │
  └─ Print summary and next steps
```

---

## Step 4: Verify the Lab (5 minutes)

After setup completes, verify everything is healthy:

```bash
make verify
```

This will check:
- ✅ kubeconfig exists
- ✅ Kubernetes cluster is accessible
- ✅ All 3 nodes are Ready
- ✅ monitoring namespace exists
- ✅ Observability pods are running
- ✅ Prometheus targets are UP
- ✅ Key metrics are available

Expected output:
```
=== K8s Under the Hood Lab Verification ===

Checking kubeconfig...
✓ kubeconfig found

Checking Kubernetes cluster...
✓ Connected to Kubernetes cluster

Checking nodes...
✓ All 3 nodes are Ready

Checking observability namespace...
✓ monitoring namespace exists

Checking observability pods...
✓ Observability pods running

Checking Prometheus targets...
✓ Prometheus has X active targets

Checking key metrics...
✓ container_memory_working_set_bytes found
✓ container_spec_memory_limit_bytes found
✓ kube_pod_container_status_restarts_total found

=== Verification Complete ===

Lab status:
  Kubernetes cluster: Ready
  Nodes: 3/3 Ready
  Observability pods: Running
  Prometheus targets: X

Next steps:
  1. Access Prometheus:
     kubectl port-forward -n monitoring svc/prometheus 9090:9090
     Open http://localhost:9090

  2. Access Grafana:
     kubectl port-forward -n monitoring svc/grafana 3000:3000
     Open http://localhost:3000 (admin/admin)

  3. Run Episode 1:
     make demo-ep01
```

---

## What Gets Provisioned

### VMs (on Proxmox 192.168.1.48)

| VM | Proxmox Node | IP | vCPU | RAM | Disk | Purpose |
|----|--------------|----|------|-----|------|---------|
| k8suth-master | pve4 (.47, 16GB host) | 192.168.1.81 | 2 | 6GB | 30GB | K3s control plane + observability |
| k8suth-worker1 | pve2 (.87, 8GB host) | 192.168.1.82 | 2 | 4GB | 30GB | K3s worker (demo workload) |
| k8suth-worker2 | pve3 (.25, 8GB host) | 192.168.1.83 | 2 | 4GB | 30GB | K3s worker |

**Total resources**: 6 vCPU, 14GB RAM, 90GB disk (across 3 physical hosts — no VMs on pve/.48)

**VM image**: Official Ubuntu 24.04 LTS cloud image. A ONE-TIME `make templates` bootstrap builds per-node template VMs (IDs 9100-9102) from the cloud image; lab VMs are then API-only full clones — no SSH to Proxmox nodes needed for day-to-day operations. Prerequisite for the bootstrap: the lab SSH key (`lab/ssh/id_rsa.pub`) authorized as `root` on pve2/pve3/pve4 and loaded in ssh-agent.

### Kubernetes Cluster

| Component | Version | Details |
|-----------|---------|---------|
| Distribution | K3s | v1.36.3+k3s1 |
| Container Runtime | containerd | Built into K3s |
| CNI | Flannel | Built into K3s |
| Pod CIDR | 10.0.0.0/8 | Flannel network |
| Service CIDR | 10.43.0.0/16 | K3s default |
| DNS | CoreDNS | Built into K3s |

### Observability Stack (monitoring namespace)

| Component | Purpose | Details |
|-----------|---------|---------|
| Prometheus | Metrics collection | 5Gi PVC, 7d retention, 15s scrape interval |
| Grafana | Visualization | 2Gi PVC, admin/admin login |
| node-exporter | Host metrics | DaemonSet on all nodes |
| kube-state-metrics | K8s object metrics | Deployment |

### Kubernetes System Pods

| Pod | Namespace | Purpose |
|-----|-----------|---------|
| coredns | kube-system | DNS |
| local-path-provisioner | kube-system | Storage provisioning |
| metrics-server | kube-system | Resource metrics |
| servicelb | kube-system | Load balancer |

### Files Created on Your Mac

| File | Location | Purpose |
|------|----------|---------|
| kubeconfig | ~/.kube/config-k8suth | Access to K3s cluster |
| SSH private key | lab/ssh/id_rsa | SSH to VMs |
| SSH public key | lab/ssh/id_rsa.pub | SSH key pair |
| Terraform state | lab/terraform/terraform.tfstate | Infrastructure state |
| Ansible inventory | lab/ansible/inventory.ini | Generated by Terraform |

---

## Accessing the Lab After Setup

### Set kubeconfig

```bash
export KUBECONFIG=~/.kube/config-k8suth
```

Or add to ~/.zshrc or ~/.bashrc for persistence:
```bash
echo 'export KUBECONFIG=~/.kube/config-k8suth' >> ~/.zshrc
source ~/.zshrc
```

### Check Cluster Status

```bash
# List nodes
kubectl get nodes

# Expected output:
# NAME             STATUS   ROLES                  AGE   VERSION
# k8suth-master    Ready    control-plane,master   5m    v1.36.3+k3s1
# k8suth-worker1   Ready    <none>                 5m    v1.36.3+k3s1
# k8suth-worker2   Ready    <none>                 5m    v1.36.3+k3s1

# List all pods
kubectl get pods -A

# Check observability pods
kubectl get pods -n monitoring

# Expected output:
# NAME                              READY   STATUS    RESTARTS   AGE
# prometheus-xxxxxxxxxx-xxxxx       1/1     Running   0          5m
# grafana-xxxxxxxxxx-xxxxx          1/1     Running   0          5m
# node-exporter-xxxxx               1/1     Running   0          5m
# kube-state-metrics-xxxxxxxxxx-xx  1/1     Running   0          5m
```

### SSH to VMs

```bash
# SSH to master
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81

# SSH to worker1
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.82

# SSH to worker2
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.83
```

### Access Prometheus

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open in browser
open http://localhost:9090

# Check targets
# Go to Status → Targets
# Should see: kubelet, kube-state-metrics, node-exporter, prometheus (all UP)
```

### Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open in browser
open http://localhost:3000

# Login
# Username: admin
# Password: admin
```

---

## Troubleshooting Setup

### Terraform fails with "API token invalid"

**Problem**: `Error: Failed to authenticate`

**Solution**:
```bash
# Verify token is set
echo $PM_API_TOKEN_ID
echo $PM_API_TOKEN_SECRET

# If empty, source ~/.proxmox-env
source ~/.proxmox-env

# Or set manually
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="your-token-secret"

# Try again
make setup
```

### Terraform fails to download the Ubuntu cloud image

**Problem**: `Error: failed to download file` during `terraform apply`

**Solution**: Each target node (pve2, pve3, pve4) needs internet access to
download the ~600MB image. Verify from each node:
```bash
ssh root@192.168.1.87 "curl -sI https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img | head -1"
```

See docs/prerequisites.md (Troubleshooting section) for how to clear the cached
image and retry.

### VM creation fails on a node

**Problem**: `Error: VM creation failed` or `no space left on device`

**Solution**: Check the target node's local-lvm free space and RAM:
```bash
ssh root@192.168.1.87 "pvesh get /nodes/pve2/storage; free -h"
```

If a node is full, adjust the `vm_nodes` placement map in
`lab/terraform/variables.tf` and re-run setup.

### Ansible fails to connect to VMs

**Problem**: `UNREACHABLE! => {"msg": "Failed to connect to the host via ssh"`

**Solution**:
```bash
# Verify VMs are running
ssh root@192.168.1.48 "qm list | grep k8suth"

# Verify SSH connectivity manually
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "echo OK"

# If it fails, wait a bit longer for VMs to boot
sleep 60

# Try again
make setup
```

### Kubernetes nodes not Ready

**Problem**: `kubectl get nodes` shows nodes as NotReady

**Solution**:
```bash
# Wait a few more minutes
sleep 300

# Check again
kubectl get nodes

# If still not ready, check logs
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "sudo journalctl -u k3s -f"
```

### Observability pods not running

**Problem**: `kubectl get pods -n monitoring` shows pods as Pending or CrashLoopBackOff

**Solution**:
```bash
# Check pod status
kubectl describe pod -n monitoring <pod-name>

# Check logs
kubectl logs -n monitoring <pod-name>

# Wait a bit longer
sleep 60

# Check again
kubectl get pods -n monitoring
```

---

## Cleanup Commands

### Clean up Episode 1 (keep lab running)

```bash
make cleanup-ep01

# This deletes demo workloads but keeps:
# - VMs
# - K3s cluster
# - Observability stack
# Ready for next episode
```

### Destroy entire lab

```bash
make teardown

# This will:
# - Destroy all VMs
# - Delete Terraform state
# - Remove kubeconfig
# - Clean up SSH keys (optional)

# Confirmation required: Type 'yes' when prompted
```

---

## Complete Setup Workflow

```bash
# 1. Navigate to lab directory
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood

# 2. Set Proxmox credentials
source ~/.proxmox-env
# OR
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="your-token-secret"

# 3. ONE-TIME: bootstrap Ubuntu templates on pve2/pve3/pve4 (needs SSH to nodes)
#    ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.47  # pve4
#    ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.87  # pve2
#    ssh-copy-id -i lab/ssh/id_rsa.pub root@192.168.1.25  # pve3
#    ssh-add lab/ssh/id_rsa
make templates

# 4. Run setup (15-20 minutes)
make setup

# 5. Verify everything (5 minutes)
make verify

# 6. Set kubeconfig
export KUBECONFIG=~/.kube/config-k8suth

# 7. Check cluster
kubectl get nodes

# 8. Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090

# 9. Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000 (admin/admin)

# 10. Run Episode 1 (Phase 2)
make demo-ep01
```

---

## Summary

| Step | Command | Time | What Happens |
|------|---------|------|--------------|
| 1 | `cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood` | 1 min | Navigate to lab |
| 2 | `export PM_API_TOKEN_ID=...` | 1 min | Set credentials |
| 3 | `make setup` | 15-20 min | Provision everything |
| 4 | `make verify` | 5 min | Verify health |
| 5 | `export KUBECONFIG=...` | 1 min | Set kubeconfig |
| 6 | `kubectl get nodes` | 1 min | Check cluster |
| **Total** | | **~25 minutes** | **Lab ready** |

---

## What's Next

After Phase 1 setup is complete, Phase 2 will add:

- Demo workload (ShopNow Payment Service)
- Failure injection scripts
- Investigation workflow
- Grafana dashboard
- Content production

Run `make demo-ep01` when Phase 2 is ready.
