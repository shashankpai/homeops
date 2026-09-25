# Troubleshooting Log — Master Index

Every real issue hit while building this lab, in one place: symptom → root
cause → fix → why it works. Organized by layer, in the order you'd hit them
building the lab from scratch (Terraform → MinIO → Ansible/K3s →
observability → episode demos).

For the full deep-dive on the observability stack specifically (scrape
config, RBAC, Grafana provisioning), see **`docs/observability.md`** — this
doc summarizes those and covers everything else.

---

## 1. Terraform / Proxmox provider

### 1.1 SSH auth errors on every `terraform apply`

- **Symptom**: `terraform apply` fails with SSH authentication errors even
  though the Proxmox API token is valid.
- **Root cause**: The Proxmox Terraform provider needs SSH access to the
  Proxmox **node** (not the VM) to perform disk customization during
  cloning (resizing, cloud-init disk injection). The provider block had no
  SSH username/agent configuration, and the nodes didn't have the lab's key
  authorized.
- **Fix**: Added explicit SSH username + `ssh-agent` usage in
  `lab/terraform/providers.tf`, and made template creation a **one-time
  bootstrap** (`make templates`) that requires the lab key
  (`lab/ssh/id_rsa.pub`) authorized as `root` on `pve2`/`pve3`/`pve4`
  (`ssh-copy-id`) with the key loaded (`ssh-add`). Day-to-day VM
  provisioning (`make apply`) then clones from those templates via the
  **API only** — no more SSH needed for routine runs.
- **Lesson**: Separate the one-time, SSH-requiring setup (template
  creation) from the repeatable, API-only path (cloning). Don't make every
  `apply` depend on SSH agent state.

### 1.2 VM template ID collisions

- **Symptom**: `make templates` failed — VM ID already in use.
- **Root cause**: Templates used dynamic index-based IDs (`9000 + index`)
  that collided with pre-existing VMs on the Proxmox cluster.
- **Fix**: Switched to a static map with fixed, out-of-the-way IDs
  (`9100`–`9102`) in `lab/terraform/templates.tf`.

### 1.3 Terraform apply took 10+ minutes per VM

- **Symptom**: Each `terraform apply` took a very long time waiting for VM
  readiness (Terraform polls for the QEMU guest agent to report an IP).
- **Root cause**: The Ubuntu cloud image doesn't ship `qemu-guest-agent`
  installed/enabled by default, so Terraform's guest-agent wait either
  times out or falls back to slow polling.
- **Fix**: Added a cloud-init snippet (`lab/terraform/snippets.tf`) that
  installs and enables `qemu-guest-agent` on first boot, carrying the full
  cloud-config (including the SSH user key) so nothing else regresses.
  VM provisioning time dropped dramatically once the agent phones home
  immediately after boot.

---

## 2. MinIO (Terraform state backend)

### 2.1 `minio/minio` image pull fails

- **Symptom**: MinIO container fails to start — image not found.
- **Root cause**: Docker Hub removed the official `minio/minio` image
  (MinIO moved distribution off Docker Hub for the AGPL-licensed build).
- **Fix**: Switched to the community-maintained fork `coollabsio/minio` in
  `lab/terraform/minio.tf`.

### 2.2 `mc` (MinIO Client) binary unavailable

- **Symptom**: Bucket-creation script fails — `mc: command not found` /
  binary download 404s.
- **Root cause**: Same upstream removal affected the `mc` client
  distribution used to create the `terraform-state` bucket and enable
  versioning.
- **Fix**: Rewrote `lab/terraform/minio-setup.sh` to use the **AWS CLI**
  (`aws s3api create-bucket`, `aws s3api put-bucket-versioning`) against
  the MinIO S3-compatible endpoint instead of `mc`.

---

## 3. Ansible / K3s install

### 3.1 `make k3s-install` printed "✓ K3s installed" but nothing was installed

- **Symptom**: Green success output, but no K3s process on any VM.
- **Root cause (two bugs)**:
  1. The Makefile recipe piped the setup script through
     `bash lab/scripts/setup.sh 2>&1 | grep -A 50 "Step 2" || true` —
     `grep` filtered most output and the trailing `|| true` swallowed the
     exit code regardless of failure.
  2. Ansible had actually aborted with
     `could not initialize the preferred locale: unsupported locale
     setting` — the Terraform/Ansible controller machine lacks
     `en_US.UTF-8`.
- **Fix**: Run `lab/scripts/setup.sh` directly (no `grep`/`|| true`
  masking) and pin `LC_ALL=C.UTF-8` (present on every Linux distro, unlike
  `en_US.UTF-8` which requires locale generation) before invoking Ansible.
- **Lesson**: Never pipe a setup script through `grep` in a Make recipe —
  you lose both the exit code and the output. A recipe that always prints
  "✓" is worse than no recipe.

### 3.2 Ansible `UNREACHABLE` — SSH connection refused

- **Symptom**: `Failed to connect to the host via ssh` for all 3 VMs.
- **Root cause**: VMs were still booting when Ansible ran — cloud-init
  hadn't finished configuring the SSH user yet.
- **Fix**: `make apply` now waits ~2 minutes after `terraform apply`
  returns before verifying SSH connectivity and handing off to Ansible.
  Manual retry: `ssh -i lab/ssh/id_rsa ubuntu@<ip> "echo OK"`, or
  `sleep 60` and re-run.

---

## 4. Observability stack (Prometheus / Grafana)

Full deep-dive (RBAC, relabeling, provisioning) lives in
**`docs/observability.md`**. Summary of every issue hit:

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | `observability-deploy` "succeeded", nothing deployed | Manifests didn't exist yet + Makefile recipe masked `kubectl apply` failures | Wrote the 5 manifests; `set -e`, no output masking |
| 2 | Only 2/5 Prometheus targets found | Default service account has no RBAC to list pods/nodes for discovery | Added `prometheus` ServiceAccount + ClusterRole + ClusterRoleBinding |
| 3 | kubelet/cAdvisor targets 404 | Relabel rule used `regex: (.+)` on an empty source label — never matches, rewrite silently skipped | Unconditional relabel: omit `regex` entirely |
| 4 | kubelet/cAdvisor targets 401 | Prometheus attaches the SA token to **discovery** API calls but not to apiserver-proxy **scrapes** | Scrape kubelet directly at `https://<node>:10250` with `bearer_token_file`, skip the apiserver proxy |
| 5 | `make verify` silently truncated | `promtool query instant "$metric"` missing the required server-URL arg; `((x++))` returns exit 1 when `x` was 0, tripping `set -e` | Pass server URL explicitly; use `x=$((x+1))` instead of `((x++))` |
| 6 | Edited `prometheus.yaml`, scrape config unchanged | Prometheus doesn't watch/reload its ConfigMap-mounted config | `kubectl rollout restart deployment/prometheus -n monitoring` after every config edit |
| 7 | Grafana dashboard import: "no datasource found" | Grafana ships with zero datasources; none was provisioned | ConfigMap-provisioned `datasources.yaml` (`isDefault: true`, uid `prometheus`) mounted at `/etc/grafana/provisioning/datasources` |
| 8 | `kubectl port-forward` to Grafana/Prometheus times out intermittently (~4/5 success) | Port-forward streams to the kubelet are created lazily; concurrent connections (Grafana UI) and pod rollouts break the tunnel | Switched both Services to `LoadBalancer` with pinned nodePorts — Grafana `:30300`, Prometheus `:30900` — direct node-IP access, no port-forward |

**Direct access (no port-forward needed):**
```
Grafana:    http://192.168.1.81:30300  (admin/admin, or any node IP)
Prometheus: http://192.168.1.81:30900                (or any node IP)
```

---

## 5. Episode 1 — OOMKilled demo

### 5.1 `curl` not found inside the demo pod

- **Symptom**: `demo.sh` and lab-guide commands using `curl` fail —
  `curl: command not found`.
- **Root cause**: The pod's image is `python:3.12-slim`, which has no
  `curl`/`wget`.
- **Fix**: Replaced every `curl` call with Python's stdlib
  `urllib.request` via `kubectl exec ... python -c '...'`, e.g.:
  ```bash
  kubectl exec -n shopnow $POD -- python -c 'import urllib.request as u; print(u.urlopen(u.Request("http://localhost:8080/allocate?mb=200", method="POST")).read().decode(), end="")'
  ```

### 5.2 `kubectl wait` raced the Deployment controller

- **Symptom**: `kubectl wait --for=condition=ready pod -l app=payment-service`
  intermittently failed with `error: no matching resources found` right
  after `kubectl apply`.
- **Root cause**: The Pod doesn't exist yet at the instant `kubectl wait`
  starts — the Deployment controller hasn't created it — so the label
  selector matches nothing and `wait` exits immediately instead of
  blocking.
- **Fix**: Wait on the **Deployment** itself instead, which cannot race:
  `kubectl rollout status deployment/payment-service -n shopnow --timeout=180s`.

### 5.3 cgroup path used the wrong pod UID format for K3s

- **Symptom**: `cat /sys/fs/cgroup/memory.max` from the node (outside the
  container) 404'd / no such file, when following the cgroup path from the
  pod UID.
- **Root cause**: K3s (containerd cgroup driver) formats the pod UID
  segment in the cgroup path with **underscores**, not the dashes shown by
  `kubectl get pod -o jsonpath='{.metadata.uid}'`. The path template needs
  `pod<uid-with-underscores>.slice`.
- **Fix**: Documented the underscore substitution in `lab-guide.md`,
  `storyboard.md`, and `demo-flow-mapping.md`, and derived the path from
  `kubectl describe pod` / `crictl inspect` output directly instead of
  hand-building it.

### 5.4 The big one: Grafana graph never showed the climb to the limit

- **Symptom**: The pod genuinely got `OOMKilled` (exit code 137, verified
  via `kubectl get pod -o jsonpath='...lastState'`), but the "Working Set
  vs Limit" Grafana panel stayed flat near the baseline the whole time —
  it never climbed toward the 128Mi limit line before dropping.
- **Root cause**: `mem-hog.py`'s `/allocate?mb=N` endpoint did **one
  instantaneous allocation** — `_held.append(bytearray(N * 1024 * 1024))`
  in a single call. The kernel's OOM killer fires within **milliseconds**
  of the cgroup crossing `memory.max`. That's far faster than:
  - Prometheus's scrape interval (15s), and
  - cAdvisor's own internal housekeeping (its cgroup stat collection is
    independent of, and can lag behind, the Prometheus scrape).

  So the metric samples straddling the kill just show the low pre-kill
  baseline, then the low post-restart baseline — the spike happened
  entirely inside the sampling gap. Confirmed via
  `curl .../api/v1/query_range` on the exact kill window: values sat flat
  at ~13-25 MiB across the whole 27-second life of the container, despite
  `lastState.terminated.reason == "OOMKilled"`.
- **Fix**: Rewrote `/allocate` in
  `episodes/01-oom-killed/manifests/payment-service.yaml` to grow the
  working set **gradually** in a background thread — `CHUNK_MB = 2` every
  `CHUNK_INTERVAL_SEC = 2` (≈1 MB/s) — instead of one lump sum. This
  stretches the climb to ~90-110 seconds, giving Prometheus 6-9 clean
  samples of the ascent before the kill.
- **Verified live** (`query_range` on the actual kill window):
  ```
  2.5 → 13.8 → 26.0 → 38.0 → 58.3 → 72.2 → 84.2 → 104.3 → 120.3 MiB
  ```
  then killed — exactly the "cliff" shape the dashboard is supposed to
  show.
- **Follow-on fixes**:
  - `demo.sh`'s restart-detection timeout bumped `120s → 180s` (the climb
    now legitimately takes ~90-110s, not instant).
  - `lab-guide.md`, `narration.md`, `demo-flow-mapping.md` updated with the
    new expected output (`allocating 200MB in 2MB steps...`) and timing.
  - `storyboard.md` flags that this phase now needs a **time-lapse /
    speed-ramp in post-production** (or live narration over the real
    ~90-110s wait) since the live recording timeline shifted.
- **Lesson**: A "realistic" memory leak that instantly overshoots a limit
  is actually *less* representative of real incidents (which build up over
  seconds-to-minutes) AND breaks metric visibility. Simulate leaks as a
  gradual climb, always slower than 2-3× your scrape interval.

### 5.5 Grafana dashboard: "Kernel OOM Kills" panel always shows nothing

- **Symptom**: In `oom-investigation.json`, the "Working Set vs Limit"
  panel works fine, but the bottom "Kernel OOM Kills" panel
  (`container_oom_events_total`) stays empty/flat across every demo run.
- **Root cause**: Verified via `query_range` across an actual confirmed
  OOMKill (exit 137, `kube_pod_container_status_last_terminated_reason=1`)
  that `container_oom_events_total{namespace="shopnow",
  container="payment-service"}` stays at exactly `0` for the entire
  container lifetime. This is an **upstream K3s/containerd limitation**:
  the kubelet's built-in cAdvisor sources container stats through
  containerd's CRI stats API, which doesn't populate the OOM event counter
  the way a standalone cAdvisor or dockershim setup would. Not fixable via
  Prometheus/Grafana config — the metric itself never gets a non-zero
  value on this runtime.
- **Fix**: None available at the Prometheus/K8s-manifest layer. Panel kept
  in the dashboard on purpose (with an updated description) as a teaching
  moment: not every metric you'd expect to exist actually populates on
  every container runtime. The real kernel-level `oom_kill` counter is
  read directly from the cgroup file in Layer 3 of the investigation
  (`cat /sys/fs/cgroup/.../memory.events` on the node) — which the
  lab-guide already does, and which IS accurate.
- **Other two panels that looked broken were actually fine**: "Last
  Termination Reason" and "Container Restarts" (`kube_pod_container_
  status_last_terminated_reason`, `kube_pod_container_status_restarts_
  total`) DO have live data — confirmed directly against Prometheus. If
  they appear empty in Grafana, it's a stale dashboard/time-range view
  (e.g., looking at it right after a `rollout restart`, which resets
  restart counts to 0 and clears `lastState` until the container is
  OOMKilled again) — not a real bug. Re-trigger `/allocate` or wait for
  the next scrape.

---

## Quick Reference — Common Commands

```bash
export KUBECONFIG=~/.kube/config-k8suth

# Cluster health
kubectl get nodes
kubectl get pods -A

# Observability direct access (no port-forward)
open http://192.168.1.81:30300   # Grafana  (admin/admin)
open http://192.168.1.81:30900   # Prometheus

# Re-run the full lab setup
make apply          # Terraform: provision VMs
make k3s-install     # Ansible: install K3s
make observability-deploy
make verify

# SSH to a node (troubleshooting only — day-to-day is API-only)
ssh -i lab/ssh/id_rsa ubuntu@192.168.1.81
```
