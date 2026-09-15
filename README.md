# homeops

A comprehensive homelab operations repository covering edge Kubernetes (Kairos), infrastructure setup, and practical SRE learning content.

## What's here

```
homeops/
  kairos/                    # Kairos edge node on Raspberry Pi 4
    cloud-config/            # boot-time configuration
    k8s/                     # Kubernetes manifests
    image/                   # custom Kairos image build
    docs/                    # implementation & troubleshooting guides
    README.md

  homelab/                   # Homelab infrastructure & networking
    vlan-setup/              # VLAN configuration
    networking/              # Network docs
    README.md

  learning/                  # Practical SRE troubleshooting episodes
    episodes/
      01-when-logs-kill-servers/   # Logrotate, disk-full incidents
      02-...
    README.md

  .github/                   # CI/CD workflows
```

## Quick start

- **Kairos setup?** → See [`kairos/README.md`](kairos/README.md) and [`kairos/docs/`](kairos/docs/)
- **Homelab infrastructure?** → See [`homelab/README.md`](homelab/README.md)
- **Learning episodes?** → See [`learning/README.md`](learning/README.md)

## Current state

| Component | Status |
|-----------|--------|
| Kairos Pi 4 | Running (VLAN 10, k3s, SSD storage, monitoring) |
| Episodes | 01 complete (logrotate), 02+ in progress |

## Secrets hygiene

**Never commit secrets.** Local build artifacts and credentials are gitignored. See individual README files for details.

---

**Generated with [Devin](https://devin.ai)**
