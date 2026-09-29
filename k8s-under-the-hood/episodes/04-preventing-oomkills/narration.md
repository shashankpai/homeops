# How do you prevent Kubernetes OOMKills?
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for 11 phases (~18 minutes).
> **Style:** Season finale — full circle. The same load that killed the
> pod in Episode 1 survives at the end, because of engineering.
> **Arc:** the problem → the fork (leak vs legit) → the anti-pattern →
> Fix A (app) → Fix B (right-size) → the safety net (alert) → the checklist.

---

## Phase 1 — Hook: The Question After the Post-Mortem (0:00 – 1:00)

[0:00]

Three episodes ago, we found the kernel killing our payment service. Two episodes ago we met the kubelet, the other killer. Last episode we built the runbook — you can now stand in a standup and say what happened, with evidence, in under a minute.

[0:25]

But there's a question that comes after every post-mortem, and it's the one that actually matters: "what are we doing so it never happens again?" And the uncomfortable answer is that most teams answer it with a bigger number. Someone opens the YAML, changes 128 to 512, and calls it prevention.

[0:45]

Today, the season finale: we're going to fix this pod properly. Both fixes — the app one and the platform one — and we're going to prove it, live, with the exact same load that killed it in Episode 1.

---

## Phase 2 — The Fork That Decides Everything (1:00 – 2:30)

[1:00]

Prevention starts with a diagnosis fork, and it's the same query we built last episode:

[1:08 — show terminal]

```promql
deriv(container_memory_working_set_bytes[10m])
```

[1:15]

The rate of growth. And there are exactly two shapes that matter. If your working set climbs linearly and never flattens — that's a leak. The memory is held and never freed. If it climbs and then plateaus — that's a legit workload that simply outgrew its pod.

[1:45]

Why does this fork decide everything? Because the fixes are completely different. A leak is an application bug — and you cannot fix an application bug with YAML. An under-sized pod is a platform decision — and you fix it with data, not guesses.

[2:05]

Our pod? Linear. We watched it for six hours across three episodes. It's a leak — a cache that forgot to have a maximum size. So let's do this in the right order: first, let's kill the most popular wrong answer.

---

## Phase 3 — The Anti-Pattern: "Just Raise the Limit" (2:30 – 4:30)

[2:30]

Someone in the room is already saying it: "bump the limit to 512." Let's do the math before doing the yoga.

[2:40 — show diagram]

```
time-to-limit = (limit − working set) / growth rate
```

[2:50]

Our leak grows at roughly one megabyte a second. At the 128 meg limit, that's about two minutes of runway. At 512 megs — about eight minutes.

[3:05]

Do you see what happened there? We quadrupled the limit and bought six minutes. The pod still dies. It just dies LATER — and "later" on a leak always means 3 a.m. instead of 3 p.m. You haven't fixed the failure, you've rescheduled it to a worse hour.

[3:30]

Raising the limit on a leak is a scheduling decision, not a fix. It's the most common OOMKill non-fix in the industry, and now you can quantify it on camera — the time-to-limit panel is on the dashboard, live.

[3:55]

There IS a legitimate version of raising the limit — right-sizing — and we'll get there. But it comes after the fork's other branch: if it's a leak, the fix is in the code.

---

## Phase 4 — Fix A: Leaks Are App Bugs (4:30 – 6:30)

[4:30]

Let's fix the leak, live. I've restarted the ramp — smaller this time, eighty megabytes on our 128-limit pod — and the working set is climbing in Grafana right now.

[4:50 — show Grafana]

Up it goes. Twenty, forty, sixty... and here's the moment. The app has a release endpoint — in the real world, this is your fix: cap the cache, bound the retention, free the memory on idle.

[5:10 — show terminal]

```bash
kubectl exec -n shopnow $POD -- python -c '... /release ...'
```

```
released; rss_mb=24.9
```

[5:25]

And watch the graph — the working set FALLS. Eighty megabytes back down to twenty-five. That's the only fix in this entire episode that actually reverses a leak. Everything else — limits, QoS, alerts — is containment.

[5:50]

Two production notes before we move on. First: leaks should be caught BEFORE production — run a soak test in staging, watch the deriv query for hours, it should trend to zero. A cache that warms up plateaus; a cache that leaks doesn't.

[6:10]

Second — and this is the honest engineering part — sometimes you can't fix the app this week. It's a vendor container, or the fix needs a release train. THAT's when containment buys you time to do it right. Which brings us to the platform fix: right-sizing from data.

---

## Phase 5 — Fix B: Right-Size From Data (6:30 – 9:30)

[6:30]

Right-sizing gets a bad reputation because most people do it with guesses. "256 sounds right." We're going to do it with measurements.

[6:42 — show terminal]

```promql
quantile_over_time(0.95, container_memory_working_set_bytes[24h])
```

[6:50]

The ninety-fifth percentile of the working set. In production you'd use days or weeks that include your worst legitimate traffic — peak hours, batch runs, deploys. For our demo: baseline is about twenty-five megabytes — that's the Python runtime idling — and the peak, the held cache under the Episode 1 load, is about two hundred twenty-five.

[7:20]

Now the sizing math, and it's three lines:

[7:25 — show diagram]

```
measured peak:            ~225Mi
headroom (×2):            ~450Mi   (bursts, fragmentation, deploys)
round to sane:            512Mi
```

[7:45]

Two-x isn't a law of nature — it's a judgment call that covers the gap between p95 and the worst day. For a payment path, you buy headroom. For a batch job, maybe you don't.

[7:55]

And one more decision in this YAML — requests. Remember Episode 2: the kubelet's eviction ranking is usage-over-requests, and BestEffort dies first. So for a critical path, we set requests EQUAL to limits:

[8:10 — show YAML]

```yaml
resources:
  requests:
    memory: 512Mi   # == limits: Guaranteed QoS
  limits:
    memory: 512Mi
```

[8:25]

That's Guaranteed QoS — the eviction-proof tier, and a hard scheduling promise for the scheduler. The payment path gets the armor.

[8:40 — show terminal]

Deploying the sized variant:

```bash
kubectl apply -f payment-service-sized.yaml
```

[9:00]

And now... the moment of the whole season. Same pod name pattern, same app, same allocate command — the exact call that killed it in Episode 1. Two hundred megabytes.

---

## Phase 6 — The Money Shot: Same Load, Survived (9:30 – 11:30)

[9:30 — show terminal]

```bash
kubectl exec -n shopnow $SIZED_POD -- python -c '... /allocate?mb=200 ...'
```

[9:40]

Watching the dashboard — the bad pod's history is right there: climb, ceiling, cliff, dead. And the sized pod now... climbing... two hundred megabytes... and it just... stays there.

[10:05]

Forty-four percent of its limit. Comfortable.

[10:15 — show terminal]

```bash
kubectl get pods -n shopnow
```

```
payment-service-...        1/1   Running   4    (the victim — 4 deaths)
payment-service-sized-...  1/1   Running   0    (the fix — zero deaths)
```

[10:35]

SAME LOAD. ZERO RESTARTS. One pod has died four times this season; its sibling, under the identical allocation, hasn't died once. That's the difference between guessing and engineering.

[11:00]

And if you're wondering "couldn't you have just... not had the leak?" — yes, and Phase 4 was that fix. Right-sizing is for the load you've measured and accept; the alert is for everything else. Which is the last piece.

---

## Phase 7 — The Safety Net: Alert Before the Kernel (11:30 – 14:00)

[11:30]

Right-sizing handles known load. The unknown needs an early-warning system — and the threshold is the ninety percent line we've been drawing on graphs all season.

[11:45]

It's already wired into the lab's Prometheus. Two rules: MemoryNearLimit — working set over ninety percent of limit for a minute — and OOMKilledRecently, which fires when the last termination was an OOMKill. The first pages you BEFORE the kernel acts. The second tells you that you were too late — open the Episode 3 runbook.

[12:15]

Let's trigger the first one, live. I'm going to push the sized pod past ninety percent — four hundred fifty megabytes of its five hundred twelve:

[12:25 — show terminal]

```bash
kubectl exec -n shopnow $SIZED_POD -- python -c '... /allocate?mb=450 ...'
```

[12:35]

Now it's climbing through four hundred... four-thirty... crossing the line at four sixty-one...

[12:50 — show Prometheus UI]

```
MemoryNearLimit   FIRING
```

[13:05]

FIRING. And look at the pod — still Running. Still alive. The alert fired with fifty-one megabytes of runway left, the kernel never had to act, and a human just got handed twenty minutes of lead time instead of a corpse.

[13:30]

That's the entire philosophy of prevention on one screen: you can't stop the kernel from enforcing your limit — you wrote the limit. What you CAN do is make sure a human sees the trajectory while it's still a warning, not a post-mortem.

---

## Phase 8 — The Last Line: Guaranteed QoS Recap (14:00 – 15:00)

[14:00]

One more prevention layer deserves its thirty seconds, because it connects the whole season. When we set requests equal to limits, we didn't just make a scheduling promise — we changed this pod's eviction rank.

[14:20 — show diagram]

```
eviction order (Episode 2):     OOMKill (Episode 1):
  BestEffort    first            kernel doesn't care about QoS
  Burstable     middle           a limit is a limit
  Guaranteed    last
```

[14:40]

Guaranteed pods are the last line of defense when a node melts down. The kernel can still OOMKill them — QoS means nothing to a cgroup limit — but the kubelet will evict everyone else first. Different killers, different protections. That asymmetry was Episode 2's lesson; the sized payment-service is that lesson, applied.

[14:55]

And for fleets of stateless pods you don't want to hand-size: the VPA can compute exactly this p95-plus-headroom math for you and recommend sizes. Just remember its two traps — it restarts pods to apply new sizes, and it will cheerfully right-size you INTO a leak, because to the VPA, a leak looks like demand. Human decides, VPA recommends.

---

## Phase 9 — The Checklist (15:00 – 16:30)

[15:00]

The whole episode, compressed into the checklist — this is the printable:

[15:05 — show full-frame]

```
PREVENT OOMKILLS:
1. MEASURE    p95/p99 working set from real traffic
2. CLASSIFY   leak (linear deriv) vs legit (plateau)
3. FIX RIGHT  leak -> fix the app | legit -> right-size
4. SIZE       peak × headroom; requests=limits for critical paths
5. ALERT      90% of limit — before the kernel, not after
6. PROVE      load-test the same load that killed it
7. REVIEW     VPA recommends, humans decide
```

[15:45]

Seven lines. Every one of them demonstrated live in the last fifteen minutes — measured with quantile queries, classified with deriv, fixed both ways, sized from data, alerted at the line, and proven with the same kill command that started this season.

[16:10]

It's in the repo — prevention-checklist.md — next to the diagnosis runbook from Episode 3. Runbook for when it happens. Checklist so it doesn't.

---

## Phase 10 — Season Wrap: Four Episodes, One System (16:30 – 17:45)

[16:30]

Look at what we built, as a system:

[16:35 — show diagram]

```
Episode 1: the kill      — WHO: the kernel, via cgroups
Episode 2: the other killer — WHO ELSE: the kubelet, via eviction
Episode 3: the runbook   — HOW to find out, fast and repeatably
Episode 4: the fix       — HOW to make sure it never pages you
```

[17:00]

A pod dies in your cluster now, and you have a complete answer: which of the two killers, how to prove it in five minutes, and how to prevent the next one — with every claim evidenced, from `memory.events` to a firing alert.

[17:20]

Everything you watched is reproducible with one command per episode — three-node K3s on Proxmox, all manifests and dashboards in the repo. Steal all of it.

---

## Phase 11 — Outro / Next Season Tease (17:45 – 18:30)

[17:45]

That's Season 1: four episodes, two killers, one runbook, one fix, and a payment service that has died four times for your education. It deserves a rest.

[18:00]

Next season, we go to the layer most engineers never debug because they've never seen it move: networking. What a ClusterIP actually IS — and I'll give you the hook now: it's an address that NO process listens on. Go check. I'll wait.

[18:20]

Subscribe if you want to see under that hood too. Thanks for watching Season 1 — go size something properly.
