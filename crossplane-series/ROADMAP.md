# Crossplane Series — Roadmap (future seasons, ideas only)

> Status: captured ideas, not commitments. Season 1 (Getting Started) is the only planned work.
> Filter for every topic: does it demo well on the local K3s lab, and does it build on the previous episode?

## Season 1 — Getting Started

| Ep | Topic | Status |
|----|-------|--------|
| 1 | Getting Started: concepts, managed resources, drift-heal, first Composition | Planned |

## Season 2 — Compositions in Depth

| Ep | Hook |
|----|------|
| 1 | Compositions beyond patch-and-transform: function-go-templating / KCL — readable templates vs patch spaghetti |
| 2 | Crossplane functions from scratch: writing your own (Go/Python pipeline step) |
| 3 | Versioning your platform API: XRD versions, conversions, deprecating safely |
| 4 | Ready-checks, dependencies and ordering between composed resources (wait-for semantics) |

## Season 3 — Platform Engineering

| Ep | Hook |
|----|------|
| 1 | A real internal developer platform: WebApp + DB + secrets bundle as one API |
| 2 | GitOps with Argo CD: platform configs + apps in the same flow |
| 3 | Multi-tenancy + RBAC: which teams can create which XRs; namespace scoping in v2 |
| 4 | Packaging the platform: Configurations (the "platform bundle" as a package) |

## Season 4 — Operations & Observability

| Ep | Hook |
|----|------|
| 1 | Drift, deletion policies and orphaning: what happens when you delete a WebApp, exactly |
| 2 | Observing Crossplane with the existing Prometheus/Grafana stack (metrics + dashboards) |
| 3 | Provider upgrades and the package lifecycle without downtime |
| 4 | Testing compositions: `crossplane render` + `crossplane beta validate` in CI |

## Season 5 — Beyond the cluster

| Ep | Hook |
|----|------|
| 1 | provider-helm + provider-sql: real external resources with no cloud |
| 2 | MinIO buckets as managed resources (the lab's MinIO LXC!) |
| 3 | Proxmox VMs via provider-terraform: Crossplane managing the machines the lab runs on |
| 4 | First cloud resource: AWS via Upbound provider (s3 bucket) — the on-ramp to real usage |
