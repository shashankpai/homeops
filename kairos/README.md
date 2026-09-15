# Kairos Edge Node Setup

Immutable Kubernetes edge node running [Kairos](https://kairos.io) on a Raspberry Pi 4 (arm64) with k3s, managed entirely from this GitHub repository.

## Goal

A single source of truth for an edge Kairos node:

- **OS image** — a custom Kairos image extending upstream `hadron`, built in GitHub Actions and published to GHCR.
- **Configuration** — cloud-config files in this repo are pulled onto the Pi on every boot via Kairos's `stages.boot.git`, so config changes land with a reboot, no re-flashing.
- **Upgrades** — atomic A/B OS upgrades triggered manually over SSH against the GHCR image, with automatic fallback to the passive image on boot failure.

## Repo layout

```
kairos/
  cloud-config/             # canonical cloud-config files (pulled by the Pi at boot)
    00_base.yaml            # users, ssh keys, k3s
    01_ssd_storage.yaml     # SSD reconciliation + local-path provisioner config
    10_git-pull.yaml        # boot-time curl+tar pull of this repo into /oem
    20_k8s_workloads.yaml   # Kairos stages to apply k8s manifests
  k8s/                      # k8s manifests (pulled by git-pull, applied by workloads stage)
    namespace.yaml          # monitoring namespace
    prometheus.yaml         # Prometheus + ConfigMap + PVC
    node-exporter.yaml      # node-exporter DaemonSet
    kube-state-metrics.yaml # kube-state-metrics Deployment
    grafana.yaml            # Grafana + ConfigMaps + PVC
  image/
    Dockerfile              # custom Kairos image extending upstream hadron
  build/                    # build artifacts
  docs/                     # implementation notes and troubleshooting
```

See `docs/` for detailed setup and troubleshooting guides.
