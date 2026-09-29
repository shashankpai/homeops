# Series Roadmap — Future Seasons (Reference)

> **Status:** ideas captured for future reference — NOT outlines or commitments.
> Filter applied to every topic: can we kill it live on the 3-node K3s lab,
> and does the evidence descend through layers (the series' DNA)?
>
> Current series structure lives in [README.md](README.md#series-structure).

---

## Season 4 — Networking: The Blind Spot Everyone Has *(top pick)*

Most platform engineers debug memory and CPU okay — then networking happens
to them. Highest search volume, best fit for the descent format. The lab is
already perfect for it (tcpdump on the Proxmox VMs, conntrack tables, VXLAN
between the three nodes).

| Ep | Hook | The layers |
|----|-------|-----------|
| 1 | What IS a ClusterIP? (No process listens on it) — `curl` works, `ss -tlnp` on every node shows nothing | kube-proxy → iptables/IPVS chains → conntrack → kernel NAT |
| 2 | The 5-second DNS delay every microservice team hits — intermittent, in-cluster only | ndots:5 → search-path expansion → conntrack race → CoreDNS under UDP |
| 3 | "Connection reset by peer" — but curl works! | keepalive vs conntrack entry expiry → NAT mismatch → kernel RST |
| 4 | Flannel under the hood — your packets, captured | VXLAN encapsulation, MTU, cross-node hop (tcpdump on the nodes) |

**Why first:** biggest knowledge gap even among senior engineers, highest
search demand, zero new lab infrastructure needed. The ClusterIP episode
("no process listens on it — go check") might be the best cold-open hook
of the whole series.

---

## Season 5 — Storage: Where Evidence Goes to Hide

| Ep | Hook |
|----|------|
| 1 | Pod stuck Pending on a PVC — who's blocking? (WaitForFirstConsumer, volume node affinity — the scheduler↔CSI handshake nobody explains) |
| 2 | "Disk full" — but `df` says 20% free (inodes vs bytes; nodefs vs imagefs; callback to Ep 2's eviction signals) |
| 3 | Stuck Terminating — finalizers and the CSI detach that never came |
| 4 | What CSI actually does on provision/delete (every actor watchable: apply → API → external controller → array) |

---

## Season 6 — The Control Plane Itself

| Ep | Hook |
|----|------|
| 1 | What `kubectl apply` REALLY does (CLI → API server → etcd → controllers; the reconcile loop made visible) |
| 2 | Kill etcd, watch the world (quorum loss live, then restore — the disaster drill) |
| 3 | A controller crashes mid-reconcile — what happens to your object? (idempotency + level-triggered design) |
| 4 | The API server says 429 — priority & fairness (self-inflicted DDoS via misconfigured operators) |

---

## Season 7 — Failure Cascades (the seasoned-SRE season)

Graduates the series from "one pod dies" to "the system dies" — strongest
differentiation territory, almost nobody makes this content. Do it when the
audience has followed through the fundamentals.

| Ep | Hook |
|----|------|
| 1 | Retry storms — one dependency slows 200ms and the cluster melts (backpressure, circuit breakers, timeouts) |
| 2 | Gray failures — 1 of 3 nodes degraded; health checks pass, users suffer |
| 3 | Preemption in action — PriorityClass evicting prod to fit a batch job (callback to Ep 2's eviction ranking) |
| 4 | The expired certificate outage — the classic, simulated safely |

---

## Honorable Mentions (fillers / shorts)

- **ImagePullBackOff** — registry auth, rate limits, image GC (high search volume, easy episode)
- **Sidecar containers** — init containers vs native sidecars, the restart-policy trap
- **Cardinality explosion** — Prometheus dying slowly from too many labels (fits the observability lab)
- **seccomp / RuntimeClass** — what the container can't do (security season seed)

---

## Suggested Order

1. **Season 4 (networking)** — biggest gap, best hooks, lab already supports it
2. **Season 5 (storage)** — natural pairing, evidence-heavy
3. **Season 6 (control plane)** — for the audience that wants to go deeper
4. **Season 7 (cascades)** — the differentiation season, once trust is built
