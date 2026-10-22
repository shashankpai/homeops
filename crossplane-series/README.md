# Crossplane Series

A demo-driven YouTube series on Crossplane v2 — turning infrastructure into Kubernetes APIs. Separate from `../k8s-under-the-hood` (long-form K8s internals) but **reuses the same Proxmox K3s lab**. Nothing cloud-specific is required: everything runs against the 3-node K3s cluster provisioned by that series.

> All commands run from your **controller machine** (the Mac with the kubeconfig). Nothing in this repo talks to Proxmox directly.

## Lab

The lab is the `k8s-under-the-hood` K3s cluster:

- Master 192.168.1.81 (pve4), workers .82/.83 (pve2/pve3)
- Kubeconfig: `~/.kube/config-k8suth` (created by `../k8s-under-the-hood make setup`)
- Existing observability stack in `monitoring` namespace (Prometheus/Grafana)

Series plan: `~/.devin/plans/plan-7771e83257001eae.md`

## Prerequisites

On the controller:

- `kubectl` (v1.36+)
- `helm` (v3.14+)
- `crossplane` CLI v2 (`crossplane beta render/trace/validate` used in the demo)
- The lab kubeconfig at `~/.kube/config-k8suth`
- Internet access from the controller (image pulls) and from worker nodes (package registry `xpkg.upbound.io`)

See `docs/prerequisites.md` for install commands and lab bring-up.

## Quick start

```bash
cd crossplane-series

# 0. One-time: bring up the K3s lab (skip if already running)
#    cd ../k8s-under-the-hood && make setup

# 1. Install Crossplane v2 + providers + functions into the lab
make crossplane-install

# 2. Verify
make verify

# 3. Run Episode 1 demo
make demo-ep01

# 4. Clean up the episode (keeps Crossplane installed)
make cleanup-ep01

# Full teardown of Crossplane itself
make crossplane-uninstall
```

## Series structure

| Episode | Topic | Status |
|---------|-------|--------|
| 1 | Crossplane Getting Started — Providers, Managed Resources, drift-heal, and your first Composition | Planned |

Future seasons (Compositions deep dive, platform engineering/GitOps, operations, cloud providers, Proxmox VMs via provider-terraform) are captured in [ROADMAP.md](ROADMAP.md).

## Layout

```
crossplane-series/
  Makefile                     # install / verify / demo-epNN / cleanup-epNN
  lab/
    versions.env                # pinned versions (Crossplane chart, providers, functions)
    install-crossplane.sh       # helm install + kubectl apply providers/functions
    uninstall-crossplane.sh
    verify.sh
    providers/                  # Provider, ProviderConfig, RBAC, DeploymentRuntimeConfig manifests
    README.md
  docs/
    prerequisites.md            # controller prereqs + lab bring-up
  episodes/
    01-getting-started/
      lab-guide.md              # step-by-step recording runbook
      storyboard.md             # video structure with timings
      narration.md              # talking points
      demo-flow-mapping.md      # concept -> command mapping
      metadata.md               # titles, description, SEO
      manifests/                # episode YAML
      scripts/demo.sh, cleanup.sh
```

## Secrets hygiene

No cloud credentials are used in this series. ProviderConfig uses the Crossplane service account's injected identity. If you later add MinIO/cloud credentials, never commit them — see top-level README.
