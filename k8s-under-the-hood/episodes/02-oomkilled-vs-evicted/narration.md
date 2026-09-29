# OOMKilled vs Evicted — They Are NOT the Same
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for all 11 phases.
> **Style:** Conversational, curiosity-driven, comparison-driven.
> **Pattern per segment:** SYMPTOM → OBSERVATION → HYPOTHESIS → COMMAND → EVIDENCE → ROOT CAUSE
> **Duration target:** ~20 minutes.

---

## Phase 1 — Intro / Hook (0:00 – 1:00)

[0:00]

Two pods died last night. Same cluster. And here's the thing — they died completely differently. One of them restarted three times. The other one... just vanished. Not restarted. Gone. Deleted off its node, recreated somewhere else, like it was never there.

[0:20 — show terminal]

```bash
kubectl get pods -n shopnow
```

```
NAME                         READY   STATUS    RESTARTS   AGE
payment-service-7d9c6b5f4-x2k8p   1/1     Running   3          12h
```

[0:30]

This is the victim from Episode 1. OOMKilled by the kernel, three times — but it's still here, still Running, because a container that gets OOMKilled just... restarts. In place.

[0:40 — show terminal]

```bash
kubectl get pods -n eviction-demo
```

```
NAME                     READY   STATUS     RESTARTS   AGE
memory-hog-5d9c6b5f4-2k8p    0/1     Evicted   0          8m
```

[0:50]

And this is the second victim. Evicted. Zero restarts — because there's nothing left to restart. In the next twenty minutes we're going to prove these two deaths had two different killers: one in the Linux kernel, and one inside the kubelet. Let's go.

---

## Phase 2 — Theory: The Two Actors (1:00 – 3:30)

[1:00]

In Episode 1 we found one killer: the kernel's OOM killer, enforcing the cgroup limit you wrote in your YAML. Container goes over 128 megabytes, kernel sends SIGKILL, exit code 137, container restarts. That story is entirely per-container.

[1:20]

The kubelet is a different kind of guardian. It doesn't watch containers — it watches the NODE. And it watches four signals:

[1:28 — show diagram]

```
kubelet eviction signals:
  memory.available     <- today's episode
  nodefs.available     <- root disk
  imagefs.available    <- image disk
  pid.available        <- process IDs
```

[1:45]

Each signal has thresholds. Defaults look like this:

```
--eviction-hard=memory.available<100Mi,nodefs.available<10%,...
```

Meaning: if available memory on this node drops below 100 megabytes, the kubelet doesn't ask permission. It starts deleting pods until the node recovers.

[2:10]

Now here's the question that matters: which pods does it delete? ALL of them? No — it ranks them. And the ranking is your QoS class. BestEffort pods — no requests, no limits — die first, always. Then Burstable pods, sorted by how much they use OVER their requests. Guaranteed pods — requests equal to limits — are the last line of defense.

[2:40]

So the mental model for this whole episode:

[2:45 — show diagram]

```
OOMKill:      container breaks ITS OWN limit  -> KERNEL kills the process
Eviction:     node runs low on memory         -> KUBELET deletes the POD

two killers, two scopes, two completely different crime scenes
```

[3:10]

And one more difference you can feel immediately: an OOMKilled pod restarts in place — the kernel killed a process, the container runtime starts a new one, same node. An evicted pod is DELETED. The Deployment controller has to notice, create a new pod, and the scheduler has to place it — hopefully somewhere with more headroom.

[3:25]

Let's set up the crime scene.

---

## Phase 3 — Setup: Deploy the Victims (3:30 – 5:00)

[3:30]

Two workloads. First, our survivor from Episode 1 — payment-service, Burstable, 64 megs request, 128 megs limit. Second, the new victims: three memory hogs, pinned to one worker node.

[3:45 — show terminal]

```bash
make demo-ep02   # or the lab-guide commands step by step
```

[3:55]

Here's the hog manifest — and I want you to notice what's NOT in it:

[4:00 — show YAML excerpt]

```yaml
# BestEffort QoS: NO resources block at all.
# No requests to protect it, no limits to kill it —
# when the node runs low, the kubelet evicts these FIRST.
```

[4:15]

No resources block. At all. No requests, no limits. That makes these pods BestEffort — the kubelet's eviction appetizer. The kernel will never OOMKill them, because there's no limit to cross. The only thing that can kill a hog... is the node running out.

[4:35]

One more setup detail — on the target worker, we've configured the kubelet's eviction threshold:

[4:42 — show terminal]

```bash
cat /etc/rancher/k3s/config.yaml
```

```
kubelet-arg:
  - "eviction-hard=memory.available<1Gi"
```

[4:55]

We raised it from the default 100 megs to 1 gig, so we don't have to fill the whole node — and so you can see that the threshold is just... kubelet configuration. A file. Not an API object. Remember that for later.

---

## Phase 4 — Baseline: The Node Is Healthy (5:00 – 6:00)

[5:00]

Before the crime, the victim's vitals:

[5:05 — show terminal]

```bash
kubectl describe node $NODE | grep -A 6 "Conditions:"
```

```
  Conditions:
    MemoryPressure   False   Thu ...
    DiskPressure     False   Thu ...
```

[5:20]

MemoryPressure: False. The node considers itself fine. In Grafana — and I'd have the Episode 2 dashboard up here — the node's available memory is sitting comfortably above the red threshold line we drew at 1 gig. That gap between the blue line and the red line? That's the crime scene we're about to consume.

[5:50]

Note the payment-service is Running on this cluster too. It'll ride through everything we're about to do. Keep an eye on it.

---

## Phase 5 — Trigger: Fill the Node (6:00 – 8:00)

[6:00]

Every hog has the same allocate endpoint we built in Episode 1. We call it, and the hogs start eating — two megs every two seconds, per pod, three pods. Deliberately slow, so the drain shows up across Prometheus's scrape intervals.

[6:15 — show terminal]

```bash
for pod in $(kubectl get pods -n eviction-demo -l app=memory-hog -o jsonpath='{.items[*].metadata.name}'); do
  kubectl exec -n eviction-demo $pod -- python -c "..."
done
```

```
allocating 256MB in 2MB steps every 2s (~256s to finish, or evicted before then); rss_mb=24.9
```

[6:30]

"Or evicted before then" — I love that this is now a real possibility. In Episode 1 the app's warning said "or OOMKilled before then". Same app, different killer this time.

[6:45 — show Grafana]

Now watch the dashboard. The blue line — node memory available — starts its long fall. Three hogs, about a megabyte per second combined. This is the mirror image of Episode 1's graph: back then we watched a CONTAINER's working set climb toward its limit. Now we're watching the NODE's available memory fall toward the kubelet's threshold.

[7:30]

And here's the QoS lens panel doing its job: the eviction-demo line climbing and climbing — with NO limit line to hit. Nothing kills these hogs per-container. They just keep eating. The payment-service line meanwhile is flat at thirty megs. Same cluster. Same pressure, building. Different fates coming.

[7:55]

Round after round. Let's see who the node calls first.

---

## Phase 6 — The Eviction (8:00 – 10:00)

[8:00 — show terminal]

```bash
kubectl get pods -n eviction-demo -w
```

[8:10]

Watch closely. The blue memory line in Grafana is getting close to the red threshold now... crossing... and—

[8:20]

```
memory-hog-5d9c6b5f4-7tq1    0/1     Evicted   0          9m
memory-hog-5d9c6b5f4-9xz3    0/1     Evicted   0          9m
```

[8:30]

EVICTED. Notice everything that's NOT here. No exit code. No restart count. No Last State, no OOMKilled, no 137. The pod isn't telling us a container died — the pod itself is gone. Failed. Deleted off this node.

[8:50 — show terminal]

Now the event — the single best line of evidence in this whole episode:

```bash
kubectl get events -n eviction-demo --sort-by=.lastTimestamp | grep -i evict
```

```
The node was low on resource: memory. Threshold quantity: 1Gi, available: 998Mi.
```

[9:15]

Read that out loud. THE NODE was low on resource MEMORY. Threshold quantity 1Gi. Available, 998 megs. That event names the killer, the weapon, the threshold, and the evidence — in one line. In Episode 1, no event ever mentioned the kernel. Here, no kernel was ever involved.

[9:40]

And payment-service? Still Running. Zero restarts. We just filled a node past its eviction threshold — and the Burstable pod didn't just survive an OOMKill, it survived EVICTION. Why? That's next.

---

## Phase 7 — Layer 5: Metrics — Watching It Happen (10:00 – 12:30)

[10:00]

Let's rewind and watch the crime in the metrics — this is the observability replay.

[10:05 — show Grafana, Panel 1]

The signature graph: node memory available, falling from about two gigs, crossing the red threshold line at one gig. The moment of crossing IS the moment of eviction. Compare this with Episode 1's cliff — the container working set hitting 128 megs. Same shape, opposite direction, completely different meaning. Episode 1: the container outgrew its box. Episode 2: the room ran out of air.

[10:45 — show Grafana, Panel 2]

Second panel: MemoryPressure. Flat at zero... zero... zero... then flipping to one exactly when the threshold crossed. That's the node's own condition — the kubelet setting a flag that says: this node is under memory pressure. And the scheduler reads it. Which is why our evicted hogs got recreated on the OTHER worker — the pressured node quietly repels new pods.

[11:15 — show Grafana, Panel 3]

Third panel: pod status reason. Three lines, one per hog. Each steps from nothing to Evicted, in sequence — the kubelet deleting them one at a time, checking the node between each kill. And notice what's missing: no restart counter climbing. Evicted pods don't restart — they get REPLACED.

[11:45 — show Grafana, Panel 4]

And the QoS lens — my favorite panel. eviction-demo climbing into the gigabytes with no ceiling in sight. shopnow, the payment-service, flat at thirty megs. Two workloads, one node, one pressure event. One died entirely. The other didn't even notice. That panel IS the lesson of this episode.

[12:15]

Three queries tell the whole story — and you can run these on any cluster:

[12:20 — show terminal]

```promql
node_memory_MemAvailable_bytes
kube_node_status_condition{condition="MemoryPressure", status="true"}
kube_pod_status_reason{reason="Evicted"}
```

---

## Phase 8 — The Ranking: Who Dies First and Why (12:30 – 15:00)

[12:30]

So why did the hogs die and payment-service live? Because eviction isn't random — it's a ranked list.

[12:40 — show diagram]

```
kubelet eviction ranking (memory pressure):
  1. BestEffort      — no requests            <- hogs, always first
  2. Burstable       — by usage OVER request  <- payment-service, but...
  3. Guaranteed      — requests == limits      <- last line of defense
  (PriorityClass breaks ties within a tier)
```

[13:05]

BestEffort pods are always first. No requests means everything they use is over-request by definition. They're the node's emergency food.

[13:20]

Then Burstable pods — and here's the nuance nobody tells you: the kubelet doesn't just look at how much you use. It looks at how much you use ABOVE your request. Payment-service is using about thirty megs. Its request is sixty-four. It's UNDER request — its usage-over-requests is negative. To the kubelet, evicting it would free almost nothing and hurt a pod that's keeping its promises.

[13:50]

So the ranking sent every hog to the gallows first. If pressure had continued — if we'd kept filling after the hogs died — payment-service would eventually be at risk too. And after ALL the Burstables... the Guaranteed pods. Requests equal to limits — as long as they stay within their requests, the node basically can't evict them without a fight. That's what Guaranteed is FOR.

[14:25]

One more layer of control: PriorityClass. Within a tier, higher priority pods survive longer. It's the tiebreaker — and in a real production cluster, it's how you say "evict the batch jobs before the payment service."

[14:50]

Compare all this to Episode 1: when the kernel OOM-killed payment-service, did its QoS class protect it? No. It was Burstable then too. The kernel doesn't know or care about QoS — a limit is a limit. Eviction is the opposite: QoS is EVERYTHING. That asymmetry is the single most useful takeaway in this episode.

---

## Phase 9 — On the Node: The Kubelet's Side (15:00 – 17:00)

[15:00]

Let's go to the node and find the killer's confession — like we did with dmesg in Episode 1.

[15:08 — show terminal, on the node]

```bash
ssh -i lab/ssh/id_rsa ubuntu@$WORKER_IP

# the threshold, as the kubelet sees it
cat /etc/rancher/k3s/config.yaml
```

```
kubelet-arg:
  - "eviction-hard=memory.available<1Gi"
```

[15:30]

The threshold, in a file. Not an API object — you can't `kubectl get` it. It's kubelet configuration, and that's worth internalizing: eviction behavior lives at the NODE level, per node, in config.

[15:50 — show terminal, on the node]

Now the log — the kubelet's own account:

```bash
sudo journalctl -u k3s-agent --since "30 min ago" | grep -i evict | tail -20
```

```
... Attempting to reclaim memory
... eviction manager: pods: ...
... Successfully evicted pod eviction-demo/memory-hog-...
```

[16:20]

Read those lines carefully and compare with Episode 1. In Episode 1, the confession was in the KERNEL's log — dmesg — "Out of memory: Killed process." Kernel vocabulary. Here, the confession is in the KUBELET's log — "eviction manager," "reclaim," "successfully evicted." Kubernetes vocabulary. Two different authors, two different logs, two different killers. This is the proof, straight from the source.

[16:50]

If you take one investigative habit from this episode: when a pod dies, ask WHICH log would confess. Container limit? The kernel's dmesg. Node pressure? The kubelet's journal. The killer's identity determines where the evidence lives.

---

## Phase 10 — The Comparison Table (17:00 – 18:30)

[17:00]

Let's put the two deaths side by side — and let's make it literal. I've re-triggered payment-service's OOMKill from Episode 1, so both corpses are fresh:

[17:10 — show terminal]

```bash
kubectl get pods -n shopnow
kubectl get pods -n eviction-demo
```

```
NAME                             STATUS    RESTARTS
payment-service-7d9c6b5f4-x2k8p  Running   4          <- OOMKilled, still alive

NAME                          STATUS     RESTARTS
memory-hog-5d9c6b5f4-2k8p     Evicted    0          <- gone from the node
```

[17:35 — show full-frame table]

| | OOMKilled | Evicted |
|---|---|---|
| Killer | Linux kernel | kubelet |
| Level | one container (cgroup) | whole pods (node) |
| Trigger | own limit exceeded | node memory.available below threshold |
| QoS protection | none | everything — BestEffort first |
| Pod after death | Running, RESTARTS +1 | Failed, gone from node |
| New pod lands | same node | elsewhere (pressured node repels) |
| Evidence | memory.events, dmesg | events, conditions, journalctl |
| Metric | last_terminated_reason=OOMKilled | kube_pod_status_reason=Evicted |

[18:15]

Every row is a clue you already collected live. This table is the episode. Screenshot it.

---

## Phase 11 — Prevention + Outro (18:30 – 20:00)

[18:30]

How do you protect yourself from each killer? Different weapons.

[18:35]

Against the KERNEL — the OOM killer — it's about the pod: right-size your limits, alert at ninety percent of limit, catch leaks before they hit the ceiling. That's Episode 4's whole topic.

[18:50]

Against the KUBELET — eviction — it's about the node: first, never run BestEffort in production. You're volunteering to be the emergency food. Second, set real requests — a pod using under its request is nearly eviction-proof. Third, requests equal to limits — Guaranteed — for the things that must survive node pressure. Fourth, PriorityClass as your tiebreaker: batch jobs die before the payment path. And fifth, know your thresholds — memory.available under 100 megs is the default, and that's shockingly late to discover in an incident.

[19:30]

Cleanup is one command, and the node recovers the moment the hogs' memory is freed — watch MemoryPressure flip back to false in the metrics. Nice full circle.

[19:45]

Next episode, we take everything we've built — the five-layer descent from Episode 1 and the two-killer distinction from today — and package it into a repeatable diagnosis runbook: pod died, no logs, where do you look FIRST. Because the answer depends on which killer you're hunting.

[19:58]

I'm running all of this on a three-node K3s cluster on Proxmox — everything's in the repo, one command to reproduce. Subscribe if you want the next layer. Go find your killer.
