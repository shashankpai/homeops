# Episode 1 — Crossplane Getting Started: Lab Guide (Recording Runbook)

**Prereqs:** `make crossplane-install` and `make verify` green. Lab (`k8s-under-the-hood`) running.
**Script:** `scripts/demo.sh` (interactive; press Enter at each pause).
**Duration target:** ~25 min raw footage.

## Before recording — 15-min checklist

```bash
cd /Users/Shashank.Pai/Proxmox/homeops/crossplane-series
make verify                     # nodes Ready, crossplane pods Running, providers Healthy
kubectl get webapps.demo.crossplane.io -A          # should be empty / no CRD yet
kubectl get ns demo-team-a, payments-team 2>/dev/null; kubectl get ns | grep -E 'demo-team-a|payments-team' || echo "clean"
crossplane version               # CLI version matches chart major.minor
```

If anything from a previous take exists: `make cleanup-ep01` first.

**Field names vs installed version:** the manifests target Crossplane v2 (`apiextensions.crossplane.io/v2`, namespaced XRs, `mode: Pipeline`). If your installed chart differs, run a dry run before recording:
`crossplane beta render manifests/04-webapp.yaml manifests/03-composition.yaml` and fix any schema mismatch then — never live.

## Segments

### A. Concepts — Crossplane vs Terraform, when and why (no terminal, ~7 min)
See `narration.md` Section A. On-screen: the comparison table (storyboard segment 2). Key points: control plane vs CLI, reconcile vs plan/apply, no state file, GitOps-native, APIs as the product vs files as the product.

### B. What did we install? (demo.sh Step 0, ~2 min)
- `kubectl get pods -n crossplane-system` — core is just a controller manager
- Count CRDs; show `providers` and `functions` as *packages*

### C. First managed resource (Step 1, ~4 min)
- Apply `01-managed-resources.yaml`; explain `forProvider.manifest`
- Show `READY/SYNCED` conditions — this is Terraform's apply, but continuous

### D. Drift fight (Step 2, ~4 min)
- `kubectl delete configmap welcome` — the thing Terraform users fear
- Watch the heal loop; contrast with `terraform plan -detailed-exitcode` cron approach

### E. Platform API (Steps 3–4, ~6 min)
- Apply XRD → a new `kind: WebApp` appears in `kubectl`
- Apply Composition; explain pipeline functions briefly (input = resources + patches)
- Apply the 9-line WebApp → full environment appears
- `crossplane beta trace webapp/payments -n default`

### F. Cleanup power + wrap (Step 5, ~2 min)
- Delete WebApp → composed environment deletes (mention deletion policies exist)
- Recap the three big ideas; tease Episode 2 (Compositions deep dive)

## Common live failures & recoveries

| Symptom | Fix on camera |
|---|---|
| Provider not Healthy after install | `kubectl describe provider/provider-kubernetes` — usually image pull; wait |
| Object stuck `Synced=False` | `kubectl describe object <name>` → look at ProviderConfig/credentials source |
| WebApp not becoming Ready | `crossplane beta trace` + `kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-auto-ready` |
| Drift heal slow (>1 min) | Reduce provider poll interval or just `kubectl -n crossplane-system delete pod -l runtime.pkg.crossplane.io/name=provider-kubernetes` to force reconcile |
