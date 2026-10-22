# Prerequisites — Crossplane Series

Everything runs from your **controller machine** (the Mac). The only infrastructure requirement is the existing `k8s-under-the-hood` K3s lab on Proxmox.

## 1. Controller tools

```bash
# kubectl (v1.36+) — already present if you run the under-the-hood lab
kubectl version --client

# helm (v3.14+)
brew install helm
helm version

# crossplane CLI v2 — matches the installed Crossplane major.minor
# macOS (homebrew):
brew install crossplane-cli
# or download a specific version:
# curl -sL "https://releases.crossplane.io/stable/v2.0.0/bin/darwin_amd64/crossplane" \
#   -o /usr/local/bin/crossplane && chmod +x /usr/local/bin/crossplane
crossplane version
```

## 2. Lab cluster (one-time)

The Crossplane series reuses the K3s cluster provisioned by `../k8s-under-the-hood`:

```bash
cd ../k8s-under-the-hood

export PM_API_TOKEN_ID="your-token-id"
export PM_API_TOKEN_SECRET="your-token-secret"

make setup      # provisions VMs, MinIO, K3s, observability
make verify     # nodes Ready, monitoring pods Running
```

This leaves the kubeconfig at `~/.kube/config-k8suth`. Verify access:

```bash
export KUBECONFIG="$HOME/.kube/config-k8suth"
kubectl get nodes
# master-01 Ready (control-plane), worker-01/02 Ready
```

If the lab is already running, only the `kubectl get nodes` check is needed.

## 3. Network access

- **Controller** must reach `charts.crossplane.io` (Helm repo) and `marketplace.upbound.io` / `xpkg.upbound.io` (function/provider packages are pulled in-cluster, but the CLI renders locally).
- **Worker nodes** must reach `xpkg.upbound.io` (provider and function images) and `registry.hub.docker.com` (demo app image). No proxy config is expected on the home network; if you use one, set `httpsProxy` in the Helm values.

## 4. Resource headroom

Crossplane core + provider-kubernetes + 2 functions adds roughly:

| Component | Pods | Memory |
|---|---|---|
| crossplane core | 1 (+ optional rbac-manager) | ~150Mi |
| provider-kubernetes | 1 | ~100Mi |
| function-patch-and-transform | 1 | ~50Mi |
| function-auto-ready | 1 | ~50Mi |
| demo app (episode 1) | 2 | ~50Mi |

Workers have 4GB each with Prometheus/Grafana already running — headroom is fine. Crossplane core is scheduled by the cluster (no taints on this lab), but if you later want it pinned to the master, set `nodeSelector` in the Helm values.

## 5. Versions

All versions are pinned in [`../lab/versions.env`](../lab/versions.env). Before recording, check for a newer stable Crossplane chart and matching CLI:

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm search repo crossplane-stable/crossplane --versions | head -5
```

Update `versions.env` so the chart, CLI, and any docs all agree on the version.
