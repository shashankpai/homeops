# Lab — Crossplane on the K3s cluster

This is the only "infrastructure" the series needs: Crossplane v2 installed into the existing `k8s-under-the-hood` K3s lab. Everything is driven by the Makefile from the controller.

## What gets installed

| Object | Purpose |
|---|---|
| Helm release `crossplane` (ns `crossplane-system`) | Crossplane core: CRDs, controllers, package manager |
| `Provider` (provider-kubernetes) | Manage in-cluster Kubernetes objects as managed resources |
| `DeploymentRuntimeConfig` | Fixed service account name `provider-kubernetes` for the provider pods |
| `ClusterRoleBinding crossplane-series:provider-kubernetes` | Grants the provider SA full access to manage objects |
| `ProviderConfig default` | `InjectedIdentity` — provider uses its own service account |
| `Function` (patch-and-transform, auto-ready) | Composition pipeline for episode 1's WebApp XR |

## Files

```
lab/
  versions.env              # pinned chart/provider/function versions
  install-crossplane.sh     # helm install + kubectl apply, waits for health
  uninstall-crossplane.sh   # removes everything installed here
  verify.sh                 # health checks
  providers/
    00-provider.yaml
    10-runtime-config.yaml
    20-rbac.yaml
    30-provider-config.yaml
    40-functions.yaml
```

## Notes

- **No credentials.** `InjectedIdentity` means the provider acts as its own service account — a great talking point for the video: "Crossplane doesn't need cloud creds to manage things in your cluster."
- **Why the RBAC binding:** Crossplane v2's rbac-manager can generate roles for provider SAs via the `crossplane.io/aggregate-to-provider` label on ClusterRoles, but an explicit ClusterRoleBinding is simpler to explain on camera and works regardless of rbac-manager mode.
- **Provider packages** are pulled by the cluster from `xpkg.upbound.io` — first `Provider` install can take ~60s.
- The episode-1 WebApp Composition composes native resources (Namespace/Deployment/Service/ConfigMap) directly — no provider needed for that part; provider-kubernetes is used for the standalone managed-resource + drift-heal segment.
