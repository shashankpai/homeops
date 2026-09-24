# Lab Architecture

## Overview

The K8s Under the Hood lab is a dedicated Kubernetes cluster on Proxmox designed for investigating Kubernetes failure modes and understanding how they manifest at every layer of the stack.

---

## Physical Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Your Mac (192.168.1.x)                       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  kubectl, terraform, ansible, port-forward              │   │
│  │  Access: SSH, Prometheus, Grafana, Kubernetes API       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              │ SSH, HTTPS, TCP                  │
│                              ↓                                   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ Home network (192.168.1.0/24)
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│                  Proxmox Cluster (4 nodes)                     │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  pve (192.168.1.48) — MAIN NODE — NO LAB VMs           │   │
│  │  Serves the cluster API endpoint (:8006) only          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  pve4 (192.168.1.47) — 16GB RAM, 4 CPU                 │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ Master VM (192.168.1.81)                         │   │   │
│  │  │ ├─ 2 vCPU, 6GB RAM, 30GB disk                   │   │   │
│  │  │ ├─ K3s server (control plane)                   │   │   │
│  │  │ ├─ etcd, API server, scheduler, controller      │   │   │
│  │  │ └─ Ubuntu 24.04 LTS cloud image                 │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  pve2 (192.168.1.87) — 8GB RAM, 4 CPU                  │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ Worker 1 VM (192.168.1.82)                      │   │   │
│  │  │ ├─ 2 vCPU, 4GB RAM, 30GB disk                   │   │   │
│  │  │ ├─ K3s agent (kubelet, containerd)              │   │   │
│  │  │ ├─ Demo workload runs here                      │   │   │
│  │  │ └─ Ubuntu 24.04 LTS cloud image                 │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  pve3 (192.168.1.25) — 8GB RAM, 4 CPU                  │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ Worker 2 VM (192.168.1.83)                      │   │   │
│  │  │ ├─ 2 vCPU, 4GB RAM, 30GB disk                   │   │   │
│  │  │ ├─ K3s agent (kubelet, containerd)              │   │   │
│  │  │ └─ Ubuntu 24.04 LTS cloud image                 │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Each target node holds a cached copy of the Ubuntu 24.04     │
│  cloud image (downloaded by Terraform, ~600MB). VM disks use  │
│  each node's local-lvm (per-node storage, not shared).        │
│                                                                 │
│  K3s nodes communicate over the home network (192.168.1.0/24) │
│                                                                 │
│  Kubernetes Internal Network (per-node, via Flannel)          │
│  ├─ Pod CIDR: 10.0.0.0/8                                      │
│  └─ Service CIDR: 10.43.0.0/16                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Kubernetes Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    K3s Kubernetes Cluster                        │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ kube-system namespace                                     │ │
│  │ ├─ coredns (DNS)                                          │ │
│  │ ├─ local-path-provisioner (storage)                       │ │
│  │ ├─ metrics-server (resource metrics)                      │ │
│  │ ├─ traefik (disabled)                                     │ │
│  │ └─ servicelb (load balancer)                              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ monitoring namespace (Observability Stack)                │ │
│  │ ├─ prometheus (metrics collection)                        │ │
│  │ ├─ grafana (visualization)                                │ │
│  │ ├─ node-exporter (DaemonSet, host metrics)               │ │
│  │ └─ kube-state-metrics (Kubernetes object metrics)        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ default namespace (Demo Workloads)                        │ │
│  │ ├─ payment-service (per-episode deployment)              │ │
│  │ └─ payment-service-svc (service)                          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Data Flow — OOMKilled Episode

### 1. Application Layer

```
ShopNow Payment Service (Flask app)
  ├─ /health — liveness probe
  ├─ /allocate?mb=N — allocate N MB of memory
  ├─ /status — show current memory usage
  └─ /metrics — Prometheus metrics (optional)
```

### 2. Container Layer

```
Container (containerd)
  ├─ Image: shopnow-payment:latest
  ├─ Memory request: 128Mi
  ├─ Memory limit: 256Mi (OOM variant) or 512Mi (fixed)
  └─ cgroup: /kubepods.slice/kubepods-burstable.slice/...
```

### 3. cgroup Layer (Linux)

```
cgroup v2 (Ubuntu 22.04+)
  ├─ memory.current — current memory usage
  ├─ memory.max — memory limit (256Mi)
  ├─ memory.stat — memory breakdown
  └─ memory.events — OOM events counter
```

### 4. Kernel Layer

```
Linux Kernel
  ├─ Memory allocator (malloc, mmap)
  ├─ Page cache
  ├─ OOM killer (when memory.current ≥ memory.max)
  └─ SIGKILL signal → process exit code 137
```

### 5. Kubernetes Layer

```
Kubernetes
  ├─ kubelet monitors container exit code
  ├─ Detects exit code 137 → OOMKilled status
  ├─ Updates Pod status: OOMKilled
  ├─ Increments restart count
  └─ Triggers restart policy (default: always)
```

### 6. Observability Layer

```
Prometheus
  ├─ Scrapes kubelet /metrics/cadvisor
  │  └─ container_memory_working_set_bytes
  │  └─ container_spec_memory_limit_bytes
  │  └─ container_oom_events_total
  │
  ├─ Scrapes kube-state-metrics
  │  └─ kube_pod_container_status_restarts_total
  │  └─ kube_pod_container_status_last_terminated_reason
  │
  └─ Scrapes node-exporter
     └─ node_memory_MemAvailable_bytes

Grafana
  └─ Visualizes metrics on OOM Investigation dashboard
```

---

## Investigation Workflow

The lab enables investigation at every layer:

```
Layer 1: Kubernetes API
  kubectl get pods
  kubectl describe pod <pod>
  kubectl get events

Layer 2: Container Runtime (containerd)
  ssh to worker node
  sudo crictl ps -a
  sudo crictl inspect <container-id>

Layer 3: cgroup
  ssh to worker node
  cat /sys/fs/cgroup/<cgroup-path>/memory.current
  cat /sys/fs/cgroup/<cgroup-path>/memory.max

Layer 4: Linux Kernel
  ssh to worker node
  sudo journalctl -k | grep -i oom
  sudo dmesg | grep -i "killed process"

Layer 5: Prometheus Metrics
  kubectl port-forward svc/prometheus 9090:9090
  Query: container_memory_working_set_bytes
```

---

## Observability Stack

### Prometheus

**Purpose**: Collect metrics from all layers

**Scrape targets**:
- `kubelet:10250/metrics` — kubelet metrics
- `kubelet:10250/metrics/cadvisor` — container metrics (memory, CPU, etc.)
- `node-exporter:9100/metrics` — host metrics (disk, network, etc.)
- `kube-state-metrics:8080/metrics` — Kubernetes object metrics (pods, deployments, etc.)
- `prometheus:9090/metrics` — Prometheus self-metrics

**Retention**: 7 days
**Scrape interval**: 15 seconds (fast enough for demo resolution)
**Storage**: 5Gi PVC (local-path-provisioner)

### Grafana

**Purpose**: Visualize metrics and investigate failures

**Dashboards**:
- OOM Investigation (Episode 1) — 7 panels showing memory usage, limits, restarts, OOM events

**Data source**: Prometheus (auto-provisioned)

**Access**: `kubectl port-forward svc/grafana 3000:3000` → http://localhost:3000

### node-exporter

**Purpose**: Export host-level metrics

**Metrics**:
- CPU, memory, disk, network
- Process metrics
- System load

**Deployment**: DaemonSet (runs on every node)

### kube-state-metrics

**Purpose**: Export Kubernetes object metrics

**Metrics**:
- Pod status, restarts, termination reason
- Deployment replicas, status
- Node status, capacity

---

## Storage

### Kubernetes Storage

The lab uses K3s's built-in `local-path-provisioner` for persistent storage:

```
PersistentVolumeClaims:
  ├─ prometheus-data (5Gi)
  │  └─ Mounted at /prometheus
  │
  └─ grafana-data (2Gi)
     └─ Mounted at /var/lib/grafana
```

**Storage class**: `local-path` (K3s default)

**Location on nodes**: `/var/lib/rancher/k3s/storage/`

### Terraform State

Terraform state is stored locally on your Mac:

```
lab/terraform/
  ├─ terraform.tfstate
  ├─ terraform.tfstate.backup
  └─ .terraform/
```

**Important**: Do NOT commit these files to git. They contain sensitive information.

---

## Networking

### External Access

Your Mac accesses the lab via:

1. **SSH**: `ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81`
2. **kubectl**: `kubectl --kubeconfig=~/.kube/config-k8suth get nodes`
3. **Port-forward**: `kubectl port-forward svc/prometheus 9090:9090`

### Internal Kubernetes Network

Pods communicate via:

1. **Pod CIDR**: `10.0.0.0/8` (Flannel CNI)
2. **Service CIDR**: `10.43.0.0/16` (ClusterIP)
3. **DNS**: CoreDNS at `10.43.0.10`

### Firewall

No firewall rules are configured. The lab assumes:

- Your Mac is on the same network as Proxmox (192.168.1.0/24)
- No egress filtering (VMs can reach the internet)

---

## Resource Allocation

### VMs (distributed across 3 physical hosts — none on pve/.48)

| Component | Proxmox Node | vCPU | RAM | Disk |
|-----------|--------------|------|-----|------|
| Master | pve4 (.47, 16GB host) | 2 | 6GB | 30GB |
| Worker 1 | pve2 (.87, 8GB host) | 2 | 4GB | 30GB |
| Worker 2 | pve3 (.25, 8GB host) | 2 | 4GB | 30GB |
| **Total** | | **6** | **14GB** | **90GB** |

Sizing rationale: each 8GB host keeps ~3GB free for the Proxmox host OS; the
16GB host comfortably fits the master plus K3s system overhead. Worker memory
is intentionally modest — demo pods use 256–512Mi limits, and smaller node
memory makes node-pressure/eviction demos (Episode 2) easier to trigger.

### Kubernetes Requests/Limits

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Prometheus | 100m | 500m | 256Mi | 512Mi |
| Grafana | 50m | 200m | 128Mi | 256Mi |
| node-exporter | 50m | 100m | 32Mi | 64Mi |
| kube-state-metrics | 50m | 100m | 64Mi | 128Mi |
| **Total** | **250m** | **900m** | **480Mi** | **960Mi** |

**Available per worker**: 2 vCPU = 2000m, 4GB = 4096Mi (master: 2000m / 6144Mi)

**Utilization**: ~12% CPU, ~23% memory per worker (plenty of room for demo workloads)

---

## Security

### SSH Access

- SSH keys stored in `lab/ssh/` (not committed to git)
- Default user: `ubuntu`
- No password authentication
- SSH agent forwarding disabled

### Kubernetes RBAC

- Default service account used for demo workloads
- Prometheus has ClusterRole for reading metrics
- No network policies (open by default)

### Proxmox API

- API token stored in environment variables (not committed to git)
- Token has full permissions (for simplicity)
- In production, use more restrictive permissions

---

## Troubleshooting

### Nodes not ready

```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

Check kubelet logs:
```bash
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81 "sudo journalctl -u k3s -f"
```

### Prometheus targets down

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets
```

Check Prometheus logs:
```bash
kubectl logs -n monitoring -l app=prometheus -f
```

### Grafana not accessible

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000
```

Check Grafana logs:
```bash
kubectl logs -n monitoring -l app=grafana -f
```

### Demo workload not deploying

```bash
kubectl describe pod -n default payment-service
kubectl logs -n default -l app=payment-service
```

---

## Next Steps

1. Review `docs/prerequisites.md` to ensure all tools are installed
2. Run `make setup` to provision the lab
3. Run `make verify` to confirm everything is healthy
4. Run `make demo-ep01` to run Episode 1
