# Observability Stack — Setup, Architecture & Troubleshooting

The lab's observability stack runs in the `monitoring` namespace and powers
all episodes (Episode 1 needs `container_memory_working_set_bytes` and
`container_spec_memory_limit_bytes` from cAdvisor).

- **Related docs**: `SETUP_COMMANDS.md` (full lab setup), `docs/prerequisites.md`
- **Manifests**: `lab/observability/`
- **Deploy**: `make observability-deploy` — **Verify**: `make verify`

---

## Quick Start

```bash
# Deploy (requires: make k3s-install done, kubeconfig at ~/.kube/config-k8suth)
make observability-deploy

# Verify everything
make verify

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090 — Status → Targets

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000 (admin/admin)
```

## What Gets Deployed

| Component | Kind | Details |
|-----------|------|---------|
| Prometheus | Deployment + Service + 5Gi PVC + ConfigMap | 15s scrape interval, 7d retention, port 9090 |
| Grafana | Deployment + Service + 2Gi PVC | admin/admin, port 3000 |
| node-exporter | DaemonSet (hostNetwork, hostPID) | Host metrics on every node, port 9100 |
| kube-state-metrics | Deployment + Service | Kubernetes object metrics, port 8080 |
| RBAC | ServiceAccount + ClusterRole + ClusterRoleBinding | Lets Prometheus discover pods/nodes via the K8s API |

### Prometheus scrape jobs (11 targets on a 3-node lab)

| Job | Targets | How |
|-----|---------|-----|
| `prometheus` | 1 | static: localhost:9090 |
| `node-exporter` | 3 (one per node) | pod discovery, keep `app=node-exporter`, rewrite address from `prometheus.io/port` annotation |
| `kube-state-metrics` | 1 | static service DNS |
| `kubelet` | 3 | node discovery, direct `https://<node>:10250/metrics` with SA bearer token |
| `cadvisor` | 3 | node discovery, direct `https://<node>:10250/metrics/cadvisor` with SA bearer token |

### Key design decisions (and why)

- **RBAC is mandatory for discovery** — `kubernetes_sd_configs` (pod/node
  discovery) requires the K8s API; the default service account cannot list
  pods or nodes, so discovery silently finds 0 targets. The `prometheus`
  ClusterRole grants `get/list/watch` on nodes (incl. `nodes/metrics`,
  `nodes/proxy`) and pods.
- **Kubelet/cAdvisor are scraped directly on `<node>:10250`** with the pod's
  service account bearer token (`bearer_token_file`), NOT via the apiserver
  proxy. Prometheus only auto-attaches the SA token for discovery API calls —
  not for scrapes — so the proxy path returns 401. Direct scrape works because
  the kubelet authorizes the SA token via SubjectAccessReview, which the
  ClusterRole satisfies.
- **ConfigMap changes do NOT reload Prometheus** — Prometheus does not watch
  its config file. After editing `prometheus.yaml`, you must either edit the
  Deployment or run:
  `kubectl rollout restart deployment/prometheus -n monitoring`
- **node-exporter runs hostNetwork + hostPID** with `/proc`, `/sys`, `/` mounted
  read-only — it must see the HOST's filesystem, not the container's.
- **Fail-fast Makefile targets** — `observability-deploy` runs `set -e` and
  waits for every deployment's pods (no `|| true` masking).

### Adding a scrape job

1. Edit the `prometheus-config` ConfigMap in `lab/observability/prometheus.yaml`
2. `make observability-deploy`
3. Restart Prometheus (ConfigMaps don't hot-reload):
   `kubectl rollout restart deployment/prometheus -n monitoring`
4. Check Status → Targets in the UI, or:
   `kubectl port-forward -n monitoring svc/prometheus 9090:9090` then
   `curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health, err: .lastError}'`

---

## Troubleshooting Log (issues we actually hit, 2026-09-24)

Every issue below was encountered and fixed during the first deployment of
this stack. Each entry: symptom → root cause → fix → why it works.

### 1. `make observability-deploy` "succeeded" but deployed nothing

- **Symptom**: Green "✓ Observability stack deployed" output, but
  `error: the path "namespace.yaml" does not exist` and no pods running.
- **Root cause (two bugs)**:
  1. `lab/observability/` did not exist at all — the Makefile and
     `verify.sh` referenced manifests that were never written.
  2. The Makefile recipe piped output through
     `bash -c '... ; echo "✓"'` with no error checking — `kubectl apply`
     failures didn't stop the recipe or fail `make`.
- **Fix**: Created the five manifests; rewrote the target with `set -e`
  and no output masking so any kubectl failure fails the target.
- **Lesson**: A Make recipe that always echoes success is worse than no
  recipe — it hides breakage. `set -e` in `bash -c` recipes.

### 2. Only 2 Prometheus targets (node-exporter/kubelet/cAdvisor missing)

- **Symptom**: `/api/v1/targets` showed only `prometheus` and
  `kube-state-metrics` (the static jobs). All `kubernetes_sd_configs` jobs
  found zero targets — silently.
- **Root cause**: Pod/node service discovery requires Kubernetes API
  access. The Prometheus pod used the namespace's **default service
  account**, which has no RBAC permissions — discovery requests are
  denied and Prometheus just reports no targets (no visible error).
- **Fix**: Added a `prometheus` ServiceAccount + ClusterRole (get/list/watch
  on nodes, nodes/metrics, nodes/proxy, pods, services, endpoints) +
  ClusterRoleBinding, and set `serviceAccountName: prometheus` on the pod.
- **Verify after fix**: `kubectl auth can-i list pods --as=system:serviceaccount:monitoring:prometheus` → yes

### 3. Kubelet/cAdvisor targets "down" with HTTP 404 Not Found

- **Symptom**: Discovery worked (targets appeared) but both jobs returned
  `server returned HTTP status 404 Not Found`.
- **Root cause**: The `__address__` relabel rule used `regex: (.+)` with no
  `source_labels` — the empty source value never matches `(.+)`, so the
  rewrite to `kubernetes.default.svc:443` was **silently skipped**. The
  scrape then went to `<node-ip>:10250` (the discovery default) but still
  requested the apiserver-proxy path `/api/v1/nodes/<n>/proxy/metrics`,
  which doesn't exist on the kubelet → 404.
- **Fix**: A plain `target_label: __address__` + `replacement:` rule with
  no `regex` always applies.
- **Lesson**: In Prometheus relabeling, `regex: (.+)` does NOT match an
  empty value — an unconditional rewrite must omit `regex` entirely.

### 4. Kubelet/cAdvisor targets "down" with HTTP 401 Unauthorized

- **Symptom**: After fixing #3, scrapes reached the apiserver proxy but got
  `401 Unauthorized`.
- **Root cause**: Prometheus automatically uses the service account token
  for **discovery** API calls, but does NOT attach it to **scrape** requests
  through `kubernetes.default.svc:443` — the apiserver proxy requires auth
  that the scraper doesn't send.
- **Fix**: Dropped the apiserver-proxy approach entirely. Scrape the kubelet
  directly at `https://<node>:10250` (`role: node` default address) with
  `bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token`
  and `tls_config: { insecure_skip_verify: true }`. The kubelet authorizes
  the SA token via SubjectAccessReview against the `nodes/metrics`
  permission in the ClusterRole.
- **Result**: kubelet and cadvisor jobs went `up` on all 3 nodes.

### 5. `make verify` showed "✓" but script had aborted mid-run

- **Symptom**: verify.sh printed checks then stopped early; piping it
  through `grep` hid the truncation and the exit status.
- **Root cause (two bugs)**:
  1. `promtool query instant "$metric"` — `promtool query instant`
     requires the **server URL as its first positional argument**; the
     metric name was being interpreted as the server. The check could
     never pass.
  2. `((METRICS_FOUND++))` — arithmetic post-increment returns exit
     status **1 when the result is 0**, and under `set -e` that aborts the
     script after the very first metric check.
- **Fix**:
  ```bash
  # before (broken)                     # after (fixed)
  promtool query instant "$metric"      promtool query instant http://localhost:9090 "$metric"
  ((METRICS_FOUND++))                    METRICS_FOUND=$((METRICS_FOUND+1))
  ```
  (The promtool query runs inside the Prometheus pod via `kubectl exec`,
  so `http://localhost:9090` is Prometheus itself.)
- **Lesson**: Bash arithmetic is a classic `set -e` trap; use
  `var=$((var+1))` for counters.

### 6. Edited prometheus.yaml but targets unchanged

- **Symptom**: `kubectl apply` succeeded, but Prometheus behavior didn't
  change after config edits.
- **Root cause**: The config lives in a ConfigMap volume; **Prometheus
  does not watch or reload its config file**. (Kubelet syncs updated
  ConfigMap files into the pod, but the running process keeps its startup
  config.)
- **Fix**: `kubectl rollout restart deployment/prometheus -n monitoring`
  after any config change. (`--web.enable-lifecycle` + `/-/reload` POST
  would be the no-downtime alternative.)
- **Lesson**: Apply ≠ reload for Prometheus. Restart the deployment after
  config changes.

### 7. Bonus context: K3s install itself had failed silently earlier

- **Symptom**: `make k3s-install` printed "✓ K3s installed" but no K3s
  existed on any VM.
- **Root cause**: The Makefile recipe ran
  `bash lab/scripts/setup.sh 2>&1 | grep -A 50 "Step 2" || true` — the
  pipeline swallowed the exit code, `grep` filtered most output, and
  Ansible had actually aborted with "could not initialize the preferred
  locale: unsupported locale setting" (the controller lacks `en_US.UTF-8`).
- **Fix**: Run the script directly (`bash lab/scripts/setup.sh`) and pin a
  portable locale: `LC_ALL=C.UTF-8` (present on every Linux distro).
- **Lesson**: Never pipe a setup script through `grep` in a Make recipe —
  you lose both the exit code and the output.

---

## Quick Diagnostic Commands

```bash
export KUBECONFIG=~/.kube/config-k8suth

# Pod status
kubectl get pods -n monitoring -o wide

# Prometheus targets (job / health / error)
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s localhost:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | "\(.labels.job) \(.health) \(.lastError)"' | sort | uniq -c

# Does a key metric have data?
curl -s localhost:9090/api/v1/query \
  --data-urlencode 'query=count(container_memory_working_set_bytes)' | jq -c '.data.result'

# Prometheus logs
kubectl logs -n monitoring -l app=prometheus --tail=50

# Can Prometheus's service account see pods/nodes?
kubectl auth can-i list pods  --as=system:serviceaccount:monitoring:prometheus
kubectl auth can-i list nodes --as=system:serviceaccount:monitoring:prometheus

# Is a scrape endpoint reachable from inside the cluster?
kubectl run curl-test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -sk https://<node-ip>:10250/metrics -H "Authorization: Bearer $(kubectl get secret -n monitoring -o jsonpath='{.items[0].data.token}' | base64 -d)"
```

## Redeploy / Clean Up

```bash
# Redeploy after editing manifests
make observability-deploy

# Restart Prometheus only (config change)
kubectl rollout restart deployment/prometheus -n monitoring

# Tear down the stack (keeps the rest of the lab)
kubectl delete namespace monitoring
```
