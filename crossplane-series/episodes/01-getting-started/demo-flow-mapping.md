# Episode 1 — Concept → Command Mapping

| Concept (what you say) | Command / manifest (what you show) |
|---|---|
| Crossplane core is small | `kubectl get pods -n crossplane-system` |
| Providers are packages | `kubectl get providers` |
| Composition functions are packages | `kubectl get functions` |
| Infrastructure as CRDs | `kubectl get crd \| grep crossplane` (count) |
| Managed resource = TF resource, in-cluster | `manifests/01-managed-resources.yaml` → `kubectl get object.kubernetes.crossplane.io` |
| Reconciliation result = conditions | `kubectl describe object demo-team-a` (READY/SYNCED) |
| No state file; API is truth | `kubectl get ns demo-team-a`, `kubectl -n demo-team-a get cm welcome` |
| Continuous drift correction | `kubectl -n demo-team-a delete cm welcome` → heal loop (demo.sh step 2) |
| Publish a new API | `kubectl apply -f manifests/02-xrd.yaml` → `kubectl get crd webapps.demo.crossplane.io` |
| The recipe behind the API | `manifests/03-composition.yaml` (pipeline: p&t → auto-ready) |
| Developer experience | `manifests/04-webapp.yaml` (9 lines) → `kubectl apply` |
| Composed resources | `kubectl -n payments-team get all,cm` |
| Observability of composition | `crossplane beta trace webapp/payments -n default` |
| Controlled teardown | `kubectl delete webapp payments -n default` → namespace gone |
