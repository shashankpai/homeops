# Getting Started — K8s Under the Hood Lab

## TL;DR (Quick Start)

```bash
# 1. Prerequisites (one-time)
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood
source ~/.proxmox-env  # Or create it with Proxmox credentials

# 2. Bring up the lab (15-20 minutes)
make setup

# 3. Verify everything
make verify

# 4. Access the lab
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
```

---

## Which Document to Follow?

### For First-Time Setup

1. **Read QUICKSTART.md** (5 minutes)
   - Understand what gets created
   - Learn how to access components

2. **Read docs/prerequisites.md** (10 minutes)
   - Install required tools
   - Create Proxmox API token
   - Set environment variables

3. **Run `make setup`** (15-20 minutes)
   - Provisions 3 VMs
   - Deploys MinIO
   - Installs K3s
   - Deploys observability stack

4. **Run `make verify`** (2 minutes)
   - Verify all nodes are Ready
   - Check all pods are Running

### For Troubleshooting

- **SETUP_COMMANDS.md** — Detailed commands and troubleshooting
- **docs/architecture.md** — Lab architecture and design

### For Multi-Controller Setup (Later)

- **MULTI_CONTROLLER_MINIO_SETUP.md** — Use MinIO from other machines

### For Running Episodes

- **QUICKSTART.md** — Run Episode 1 section
- **PHASE2_CHECKLIST.md** — Phase 2 tasks

---

## Quick Reference

| Question | Answer |
|----------|--------|
| **How do I set up the lab?** | `make setup` |
| **How do I verify it works?** | `make verify` |
| **How do I access Kubernetes?** | `export KUBECONFIG=~/.kube/config-k8suth && kubectl get nodes` |
| **How do I access Prometheus?** | `kubectl port-forward -n monitoring svc/prometheus 9090:9090` |
| **How do I access Grafana?** | `kubectl port-forward -n monitoring svc/grafana 3000:3000` (admin/admin) |
| **How do I access MinIO?** | `http://192.168.1.90:9001` (minioadmin/minioadmin123) |
| **How do I run Episode 1?** | `make demo-ep01` |
| **How do I clean up Episode 1?** | `make cleanup-ep01` |
| **How do I destroy the lab?** | `make teardown` |
| **What commands are available?** | `make help` |

---

## Prerequisites Checklist

Before running `make setup`, ensure you have:

- [ ] **Terraform** (v1.5+) — `terraform version`
- [ ] **Ansible** (v2.10+) — `ansible --version`
- [ ] **kubectl** (v1.36+) — `kubectl version --client`
- [ ] **jq** — `jq --version`
- [ ] **Proxmox API token** — Created on Proxmox cluster
- [ ] **Environment variables set** — `$PM_API_TOKEN_ID` and `$PM_API_TOKEN_SECRET`

See **docs/prerequisites.md** for detailed setup.

---

## What Gets Created

| Component | Details |
|-----------|---------|
| **Master VM** | 192.168.1.81 (2 vCPU, 6GB RAM) on pve4 |
| **Worker 1 VM** | 192.168.1.82 (2 vCPU, 4GB RAM) on pve2 |
| **Worker 2 VM** | 192.168.1.83 (2 vCPU, 4GB RAM) on pve3 |
| **MinIO** | 192.168.1.90 (Docker container on master) |
| **K3s** | v1.36.3+k3s1 |
| **Prometheus** | Metrics collection |
| **Grafana** | Visualization (admin/admin) |
| **kubeconfig** | ~/.kube/config-k8suth |

---

## Step-by-Step Setup (Advanced)

If you want to deploy components separately:

```bash
# 1. Initialize Terraform
make tf-init

# 2. Provision VMs and MinIO
make tf-apply

# 3. Install K3s
make k3s-install

# 4. Deploy observability stack
make observability-deploy

# 5. Verify
make verify
```

See **Makefile** for all available targets.

---

## Common Tasks

### Access the Kubernetes Cluster

```bash
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
kubectl get pods -A
```

### Access Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090
```

### Access Grafana

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000
# Login: admin / admin
```

### Access MinIO Console

```bash
# Open http://192.168.1.90:9001
# Login: minioadmin / minioadmin123
```

### Check MinIO Status

```bash
make minio-status
```

### Run Episode 1 (OOMKilled)

```bash
make demo-ep01
```

### Clean Up Episode 1

```bash
make cleanup-ep01
```

### Destroy the Lab

```bash
make teardown
```

---

## Troubleshooting

### Terraform fails with "API token invalid"

```bash
# Verify token is set
echo $PM_API_TOKEN_ID
echo $PM_API_TOKEN_SECRET

# If empty, source ~/.proxmox-env
source ~/.proxmox-env
```

### Ansible fails to connect to VMs

```bash
# Verify VMs are running
ssh root@192.168.1.48 "qm list | grep k8suth"

# Test SSH manually
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "echo OK"
```

### MinIO is not responding

```bash
# Check if container is running
ssh ubuntu@192.168.1.81 "docker ps | grep minio"

# Check logs
ssh ubuntu@192.168.1.81 "docker logs minio"
```

See **SETUP_COMMANDS.md** for more troubleshooting.

---

## Documentation Map

```
GETTING_STARTED.md (this file)
  ├─ QUICKSTART.md (main guide)
  ├─ docs/prerequisites.md (tool setup)
  ├─ docs/architecture.md (design details)
  ├─ SETUP_COMMANDS.md (detailed commands)
  ├─ README.md (series overview)
  ├─ PHASE2_CHECKLIST.md (phase 2 tasks)
  ├─ MULTI_CONTROLLER_MINIO_SETUP.md (multi-controller)
  ├─ Makefile (available commands)
  └─ lab/
     ├─ terraform/ (infrastructure code)
     ├─ ansible/ (K3s installation)
     ├─ scripts/ (orchestration)
     └─ observability/ (Prometheus, Grafana)
```

---

## Next Steps

1. **Read QUICKSTART.md** (5 minutes)
2. **Read docs/prerequisites.md** (10 minutes)
3. **Run `make setup`** (15-20 minutes)
4. **Run `make verify`** (2 minutes)
5. **Access the lab** and explore!

---

## Support

- **Setup issues?** → SETUP_COMMANDS.md (Troubleshooting)
- **Architecture questions?** → docs/architecture.md
- **Multi-controller setup?** → MULTI_CONTROLLER_MINIO_SETUP.md
- **Available commands?** → `make help`

---

**Ready to get started?**

```bash
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood
source ~/.proxmox-env
make setup
```
