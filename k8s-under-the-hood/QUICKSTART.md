# Quick Start — K8s Under the Hood Lab

## New Location

This project has been moved to the homeops repository:

```
/Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood/
```

All commands below assume you're in this directory.

---

## Prerequisites (one-time)

### 1. Create Proxmox API Token

SSH to your Proxmox cluster and create a token (works for all nodes):

```bash
ssh root@192.168.1.48
pveum user token add root@pam k8s-under-the-hood --privsep 0
# Copy the secret shown
```

### 2. Set Environment Variables

```bash
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<secret-from-above>"
```

Or create `~/.proxmox-env` for persistence:

```bash
cat > ~/.proxmox-env << 'EOF'
export PM_API_TOKEN_ID="root@pam!k8s-under-the-hood"
export PM_API_TOKEN_SECRET="<your-secret>"
EOF

chmod 600 ~/.proxmox-env
source ~/.proxmox-env
```

### 3. One-Time SSH Access for Template Bootstrap

The **first** setup bootstraps Ubuntu templates on each Proxmox node. This one-time step needs SSH access to the nodes (afterwards, everything is API-only):

```bash
# Authorize your key on each node
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.47  # pve4
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.87  # pve2
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.25  # pve3

# Load key in ssh-agent (provider reads agent, NOT ~/.ssh/config)
ssh-add ~/.ssh/id_ed25519
```

### 4. Verify Prerequisites

```bash
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood
terraform version      # v1.5+
ansible --version      # v2.10+
kubectl version --client  # v1.36+
jq --version          # any version
```

See `docs/prerequisites.md` for detailed setup.

---

## Bring Up the Lab (Phase 1)

### One-Command Setup

```bash
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood

# Set credentials
source ~/.proxmox-env

# Run setup (15-20 minutes, first run downloads Ubuntu images)
make setup

# Verify everything
make verify
```

### What Gets Created

| Component | Details |
|-----------|---------|
| **VMs** | 3 Ubuntu 24.04 VMs across 3 physical Proxmox hosts |
| **Master** | 2 vCPU, 6GB RAM on pve4 (.47) → 192.168.1.81 |
| **Worker 1** | 2 vCPU, 4GB RAM on pve2 (.87) → 192.168.1.82 |
| **Worker 2** | 2 vCPU, 4GB RAM on pve3 (.25) → 192.168.1.83 |
| **K3s** | v1.36.3+k3s1 (latest stable) |
| **Observability** | Prometheus, Grafana, node-exporter, kube-state-metrics |
| **kubeconfig** | `~/.kube/config-k8suth` |

### MinIO State Backend

MinIO is automatically deployed as an LXC container on the master node:

```
MinIO API:     http://192.168.1.90:9000
MinIO Console: http://192.168.1.90:9001
Credentials:   minioadmin / minioadmin123
```

MinIO stores Terraform state for multi-controller access. See `MULTI_CONTROLLER_MINIO_SETUP.md` for details on using MinIO as your Terraform backend from other controllers.

### Access the Lab

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/config-k8suth

# Check cluster
kubectl get nodes

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000 (admin/admin)

# Access MinIO Console
# Open http://192.168.1.90:9001 (minioadmin/minioadmin123)
```

---

## Run Episode 1 (Phase 2 — Coming Soon)

```bash
make demo-ep01
```

---

## Cleanup

### Clean up Episode 1 (keep lab running)

```bash
make cleanup-ep01
```

### Destroy entire lab

```bash
make teardown
# Confirm with 'yes' when prompted
```

---

## Documentation

- **README.md** — Series overview, architecture, investigation workflow
- **docs/prerequisites.md** — Detailed tool setup, Proxmox requirements, troubleshooting
- **docs/architecture.md** — Lab architecture, data flows, resource allocation
- **SETUP_COMMANDS.md** — Complete command reference and troubleshooting
- **PHASE2_CHECKLIST.md** — Phase 2 tasks (demo workloads, episode scripts)
- **PROGRESS.md** — What was built in Phase 1
- **DELIVERABLES.md** — Complete file list and specifications

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

### Ubuntu cloud image download fails

Each target node (pve2, pve3, pve4) needs internet access. Verify:

```bash
ssh root@192.168.1.87 "curl -sI https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img | head -1"
```

### Ansible fails to connect to VMs

```bash
# Verify VMs are running
ssh root@192.168.1.48 "qm list | grep k8suth"

# Test SSH manually
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "echo OK"
```

See `docs/prerequisites.md` for more troubleshooting.

---

## Project Structure

```
k8s-under-the-hood/
├── README.md                    # Series overview
├── QUICKSTART.md               # This file
├── SETUP_COMMANDS.md           # Complete command reference
├── PHASE2_CHECKLIST.md         # Phase 2 tasks
├── PROGRESS.md                 # What was built
├── DELIVERABLES.md             # Specifications
├── Makefile                    # make setup, verify, demo-ep01, teardown
├── .gitignore                  # Excludes secrets, state, SSH keys
│
├── docs/
│   ├── prerequisites.md        # Tool setup, Proxmox requirements
│   └── architecture.md         # Lab architecture, diagrams
│
├── lab/
│   ├── terraform/              # Proxmox VM provisioning (IaC)
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   ├── ansible/                # K3s installation
│   │   ├── k3s-cluster.yml
│   │   ├── inventory.ini.tpl
│   │   ├── group_vars/
│   │   └── requirements.yml
│   ├── scripts/                # Orchestration
│   │   ├── setup.sh
│   │   ├── verify.sh
│   │   └── teardown.sh
│   └── observability/          # Prometheus, Grafana manifests (Phase 2)
│
└── episodes/
    └── 01-oom-killed/          # Episode 1: OOMKilled investigation (Phase 2)
        ├── scripts/
        ├── dashboards/
        └── content/
```

---

## Next Steps

1. ✅ **Phase 1 Complete**: Infrastructure and orchestration
2. ⏳ **Phase 2**: Demo workloads, failure injection, investigation scripts
3. 🎬 **Content Production**: Short-form and long-form videos

See `PHASE2_CHECKLIST.md` for detailed Phase 2 tasks.

---

## Support

- Detailed troubleshooting: `docs/prerequisites.md`
- Complete command reference: `SETUP_COMMANDS.md`
- Architecture details: `docs/architecture.md`
- Phase 2 planning: `PHASE2_CHECKLIST.md`

---

**Ready to bring up the lab?**

```bash
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood
source ~/.proxmox-env
make setup
```
