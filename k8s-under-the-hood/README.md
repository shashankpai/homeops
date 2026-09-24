# Kubernetes Under the Hood + Observability Lab Series

A practical, demo-driven YouTube series that takes real Kubernetes failures, reproduces them in a lab, explains what happens underneath, observes them with Prometheus/Grafana, troubleshoots them, fixes them, and teaches the lessons.

**Goal**: Not generic Kubernetes tutorials. Real SRE/platform-engineering investigations.

---

## Quick Start

### Prerequisites

On your Mac, ensure you have:
- `terraform` (v1.5+)
- `ansible` (v2.10+)
- `kubectl` (v1.36+)
- `jq`
- SSH keys (or generate new ones)

See `docs/prerequisites.md` for detailed setup.

### Set up the lab (one-time)

```bash
# Clone this repo
cd /Users/Shashank.Pai/Proxmox/homeops/k8s-under-the-hood

# Configure Proxmox credentials
export PM_API_TOKEN_ID="your-token-id"
export PM_API_TOKEN_SECRET="your-token-secret"
# OR create ~/.proxmox-env with the above

# Provision VMs, install K3s, deploy observability
make setup

# Verify everything is healthy
make verify
```

This creates:
- 3 Ubuntu VMs on Proxmox, distributed across 3 physical hosts
  (master on pve4/.47, workers on pve2/.87 and pve3/.25 — no VMs on pve/.48)
- MinIO LXC container (S3-compatible state backend) on master
- K3s cluster (v1.36.3+k3s1)
- Prometheus + Grafana + node-exporter + kube-state-metrics
- kubeconfig at `~/.kube/config-k8suth`

> **Note**: One Proxmox API token (created at the Datacenter level) manages
> the entire cluster — see `docs/prerequisites.md` for creation commands.
> VMs are created from the official Ubuntu 24.04 cloud image, downloaded
> directly to each target node by Terraform (no template VM needed).

### Run Episode 1 — OOMKilled

```bash
# Deploy the demo workload and trigger OOMKill
make demo-ep01

# This will:
# 1. Deploy ShopNow Payment Service (memory-hungry variant)
# 2. Trigger OOM by allocating memory beyond the cgroup limit
# 3. Show the pod being OOMKilled
# 4. Run investigation commands across all 5 layers
# 5. Display Grafana dashboard with the OOM event
```

### Clean up the episode (keep lab running)

```bash
make cleanup-ep01

# This deletes the demo workloads but keeps the lab and observability stack running
# Ready for the next episode
```

### Destroy the entire lab

```bash
make teardown

# This destroys all VMs and cleans up Terraform state
```

---

## Series Structure

### Season 1 — Kubernetes Resource & Failure Internals

| Episode | Topic | Status |
|---------|-------|--------|
| 1 | What REALLY happens when Kubernetes OOMKills a Pod? | In Progress |
| 2 | OOMKilled vs Evicted — They Are NOT the Same | Planned |
| 3 | How do you actually diagnose an OOMKilled Pod? | Planned |
| 4 | How do you prevent Kubernetes OOMKills? | Planned |

### Season 2 — CPU & Resource Behavior

| Episode | Topic | Status |
|---------|-------|--------|
| 5 | CPU throttling — why your Pod is slow even when CPU isn't 100% | Planned |
| 6 | Requests vs Limits — what Kubernetes REALLY does with them | Planned |
| 7 | Kubernetes QoS Classes — Guaranteed, Burstable and BestEffort | Planned |

### Season 3 — Kubernetes Failure Modes

| Episode | Topic | Status |
|---------|-------|--------|
| 8 | CrashLoopBackOff — Kubernetes isn't broken | Planned |
| 9 | Kubernetes Probes — how a healthy container gets restarted | Planned |
| 10 | Pod Pending — why Kubernetes refuses to schedule your Pod | Planned |

---

## Lab Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Proxmox Cluster (4 nodes)                      │
│                                                             │
│  pve (192.168.1.48) — main node — NO LAB VMs              │
│  (serves the cluster API endpoint :8006 only)             │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  pve4 (192.168.1.47, 16GB)                            │ │
│  │  └─ Master (192.168.1.81) — 2 vCPU, 6GB RAM          │ │
│  │     └─ K3s server (control plane + etcd)             │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  pve2 (192.168.1.87, 8GB)                             │ │
│  │  └─ Worker 1 (192.168.1.82) — 2 vCPU, 4GB RAM        │ │
│  │     └─ K3s agent (demo workloads)                    │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  pve3 (192.168.1.25, 8GB)                             │ │
│  │  └─ Worker 2 (192.168.1.83) — 2 vCPU, 4GB RAM        │ │
│  │     └─ K3s agent                                      │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  K3s nodes communicate over the home network                │
│  (192.168.1.0/24). Ubuntu 24.04 cloud images are           │
│  downloaded directly to each target node by Terraform.     │
│                                                             │
│  Observability Stack (monitoring namespace, in-cluster)   │
│  ├─ Prometheus (scrapes kubelet, cAdvisor, etc)            │
│  ├─ Grafana (dashboards)                                   │
│  ├─ node-exporter (DaemonSet)                              │
│  └─ kube-state-metrics (pod/deployment metrics)            │
│                                                             │
│  Demo Workload (default namespace)                          │
│  └─ ShopNow Payment Service (per-episode)                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Investigation Workflow

Every episode follows this pattern:

```
REAL PROBLEM
     ↓
REPRODUCE IT
     ↓
WHAT DOES KUBERNETES SHOW?
     ↓
WHAT IS HAPPENING UNDER THE HOOD?
     ↓
WHAT DO LINUX / KERNEL / CONTAINER RUNTIME DO?
     ↓
WHAT DO METRICS SHOW?
     ↓
HOW DO WE INVESTIGATE?
     ↓
ROOT CAUSE
     ↓
FIX
     ↓
VERIFY
     ↓
PREVENT
```

---

## File Structure

```
k8s-under-the-hood/
├── README.md                          # This file
├── Makefile                           # Orchestration targets
│
├── lab/                               # Reusable infrastructure
│   ├── terraform/                     # Proxmox VM provisioning
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── providers.tf
│   │   ├── outputs.tf
│   │   └── cloud-init.yaml
│   │
│   ├── ansible/                       # K3s installation
│   │   ├── k3s-cluster.yml
│   │   ├── inventory.ini.tpl
│   │   ├── group_vars/all.yml
│   │   └── requirements.yml
│   │
│   ├── observability/                 # Prometheus, Grafana, etc
│   │   ├── namespace.yaml
│   │   ├── prometheus.yaml
│   │   ├── grafana.yaml
│   │   ├── node-exporter.yaml
│   │   ├── kube-state-metrics.yaml
│   │   └── dashboards/
│   │       └── oom-investigation.json
│   │
│   └── scripts/                       # Lab setup/teardown
│       ├── setup.sh
│       ├── teardown.sh
│       └── verify.sh
│
├── episodes/
│   └── 01-oom-killed/                 # Episode 1: OOMKilled
│       ├── README.md
│       ├── manifests/
│       │   ├── payment-service.yaml
│       │   ├── payment-service-oom.yaml
│       │   └── payment-service-fixed.yaml
│       ├── scripts/
│       │   ├── demo.sh
│       │   ├── trigger-oom.sh
│       │   ├── investigate.sh
│       │   └── cleanup.sh
│       ├── promql/
│       │   └── queries.md
│       ├── dashboards/
│       │   └── oom-investigation.json
│       ├── troubleshooting.md
│       └── content/
│           ├── short-form-script.md
│           ├── long-form-outline.md
│           └── shot-list.md
│
└── docs/
    ├── prerequisites.md
    └── architecture.md
```

---

## Accessing the Lab

### SSH to VMs

```bash
# Master
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81

# Worker 1
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.82

# Worker 2
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.83
```

### Kubernetes

```bash
export KUBECONFIG=~/.kube/config-k8suth
kubectl get nodes
kubectl get pods -A
```

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090
```

### Grafana

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000
# Login: admin / admin
```

---

## Troubleshooting

See `docs/troubleshooting.md` for common issues and solutions.

---

## References

- **K3s**: https://docs.k3s.io/
- **Kubernetes**: https://kubernetes.io/docs/
- **Prometheus**: https://prometheus.io/docs/
- **Grafana**: https://grafana.com/docs/
- **cAdvisor**: https://github.com/google/cadvisor

---

## License

This project is provided as-is for educational purposes.
