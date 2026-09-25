# What REALLY Happens When Kubernetes OOMKills a Pod?
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for all 16 phases.
> **Style:** Conversational, curiosity-driven, progressive descent.
> **Pattern per layer:** SYMPTOM → OBSERVATION → HYPOTHESIS → COMMAND → EVIDENCE → ROOT CAUSE → (repeat one layer deeper)

---

## Phase 1 — Intro / Hook (0:00 – 1:30)

[0:00]

Your pod restarted last night. Nobody touched it. Nobody deployed. You check the logs — and this is the creepy part — the logs show nothing. No exception. No stack trace. Not even a goodbye. The application was running along, and then... it wasn't.

[0:20]

So you do what everyone does first:

[0:24 — show terminal]

```bash
kubectl describe pod -n shopnow payment-service-7d9c6b5f4-x2k8p
```

And there it is, buried in the status:

```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

[0:40]

OOMKilled. Exit code 137. And here's the question nobody stops to ask: WHO actually killed this container? Because — and this is the thing — Kubernetes will tell you it didn't. Kubernetes doesn't kill containers for memory. It never has.

[1:00]

In this episode we're going to descend through five layers — from the Kubernetes API, down into the node, into the container runtime, into the cgroup where your memory limit actually lives, and finally to the kernel itself — to find the actual killer, with the actual murder weapon, in the kernel's own log files.

[1:15]

I'm running this on a three-node K3s cluster built on Proxmox VMs, with a full observability stack, so we can watch the whole thing happen live. Let's go find the killer.

---

## Phase 2 — What Is a Memory Limit, Really? (1:30 – 4:00)

[1:30]

Before we reproduce the crime, we need to understand the setup. Because the most important fact about this episode is a misconception: people think Kubernetes enforces memory limits.

It doesn't.

[1:45]

Here's what ACTUALLY happens when you write this in your deployment:

[1:50 — show YAML]

```yaml
resources:
  requests:
    memory: 64Mi
  limits:
    memory: 128Mi
```

[2:00]

Two numbers. And they do completely different things. The REQUEST, 64 megabytes — that's for the scheduler. The scheduler reads requests to decide which node the pod lands on. That's its whole job. Once the pod is scheduled, the request is basically done.

[2:20]

The LIMIT — 128 megabytes — that's the interesting one. Watch what happens at container start, step by step:

[2:28 — show diagram]

```
kubelet
  -> tells containerd: "start this container, memory limit 128Mi"
       -> containerd creates a CGROUP on the node
            -> writes memory.max = 134217728   (128 MiB)
                 -> ...and walks away.
```

[2:45]

That's it. That's the whole enforcement mechanism. A single file on the node's filesystem. Kubernetes doesn't sit there watching your container's memory. There's no kubelet process counting your bytes. The limit becomes a cgroup file, and from that moment on, it's between your container and the Linux kernel.

[3:05]

And what is a cgroup? It's a kernel feature that groups processes and applies resource rules to them. Your container's processes all live inside a cgroup, and the kernel enforces `memory.max` on everything inside it. If the kernel can't satisfy that rule... something dies. We'll see exactly what, and how, at Layer 3 and Layer 4.

[3:30]

One more piece of setup: QoS classes. When requests equal limits, your pod is Guaranteed. When requests are less than limits — like ours, 64 less than 128 — it's Burstable. No resources at all, BestEffort. Keep that in the back of your mind. It matters for a completely different kind of memory kill, and we'll come back to it.

[3:50]

Okay. Enough theory. Let's deploy a victim.

---

## Phase 3 — Deploy the Workload (4:00 – 6:00)

[4:00]

This is the ShopNow Payment Service. It's a deliberately simple Python app — but it has one special power. I can tell it, over HTTP, to allocate and hold as much memory as I want. One endpoint. That's our murder weapon for later.

[4:18]

The manifest is in the repo:

[4:20 — show terminal]

```bash
kubectl apply -f episodes/01-oom-killed/manifests/payment-service.yaml
```

```
namespace/shopnow created
configmap/payment-service-code created
deployment.apps/payment-service created
service/payment-service created
```

[4:35]

Note what the deployment says: requests 64 megabytes, limits 128 megabytes. Everything we just talked about. Burstable. And the app runs from a ConfigMap — no image build needed, it's just a Python file mounted into a stock Python image.

[4:55]

Let's wait for it to be ready and note which node it landed on:

[4:58 — show terminal]

```bash
kubectl wait --for=condition=ready pod -l app=payment-service -n shopnow --timeout=180s
POD=$(kubectl get pods -n shopnow -l app=payment-service -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl get pod -n shopnow $POD -o jsonpath='{.spec.nodeName}')
echo "Pod: $POD | Node: $NODE"
```

[5:20]

Pod: payment-service-7d9c6b5f4-x2k8p. Node: k8s-uth-2. Keep that node name in mind — we're going to SSH into it later, because that's where the real evidence lives.

---

## Phase 4 — Baseline: Everything Looks Healthy (6:00 – 8:00)

[6:00]

Before we commit the crime, let's establish that the victim is healthy.

[6:05 — show terminal]

```bash
kubectl get pod -n shopnow $POD
```

```
NAME                         READY   STATUS    RESTARTS   AGE
payment-service-7d9c6b5f4-x2k8p   1/1     Running   0          30s
```

[6:15]

Running. Zero restarts. Now, what's it using?

[6:18 — show terminal]

```bash
kubectl exec -n shopnow $POD -- curl -s http://localhost:8080/usage
```

```
rss_mb=18.4
```

[6:28]

Eighteen megabytes out of a 128 megabyte limit. Comfortable. But here's my favorite part of this whole setup. Remember when I said the limit is just a file on the node? We can read that file FROM INSIDE the container:

[6:45 — show terminal]

```bash
kubectl exec -n shopnow $POD -- cat /sys/fs/cgroup/memory.max
```

```
134217728
```

[6:58]

One hundred thirty-four million, two hundred seventeen thousand, seven hundred twenty-eight bytes. Pull up a calculator: that's exactly 128 times 1024 times 1024. Your YAML `limits.memory: 128Mi`, as a number, in a file, on the node's disk. That file is the entire enforcement of your memory limit. Kubernetes wrote it and walked away.

[7:25]

If you're following along with the Grafana dashboard from the lab guide, now's the time to open the "Working Set vs Limit" panel. Working set's at twenty-ish megs, limit line at 128. Big gap. Healthy.

[7:45]

Alright. Everything is healthy. Let's kill it.

---

## Phase 5 — Trigger the OOMKill (8:00 – 10:00)

[8:00]

The app has an endpoint called allocate. I'm going to ask it for 200 megabytes — on a 128 megabyte limit.

[8:10 — show terminal]

```bash
kubectl exec -n shopnow $POD -- curl -s -X POST "http://localhost:8080/allocate?mb=200"
```

```
allocated 200 MB; rss_mb=219.7
```

[8:22]

Allocated two hundred megabytes. It's holding it — never freeing — like a cache that forgot to have a maximum size. This is your classic production memory leak or runaway cache, compressed into one HTTP call.

[8:38]

Now, watch what the kernel does. And I want you to keep an eye on two places: the restart counter...

[8:48 — show terminal]

```bash
kubectl get pods -n shopnow -w
```

[8:55 — narrate over the watch]

The working set is past the limit... the kernel's memory allocator inside that cgroup cannot satisfy the allocation within memory.max... and — there it goes.

```
NAME                         READY   STATUS    RESTARTS   AGE
payment-service-7d9c6b5f4-x2k8p   1/1     Running   1          2m
```

[9:20]

Restart count just went from zero to one. The container died and Kubernetes restarted it, because that's what a Deployment does — restartPolicy Always.

[9:32]

And if you were watching Grafana — the working set line rocketed up, hit the limit, and dropped to the floor. That vertical drop is the death. Then a fresh container starts low. That sawtooth shape — climb, cliff, restart — is the signature of an OOM loop. If you ever see that shape in production, you already know what it is.

[9:55]

So the pod is dead and reborn. Now — who killed it? Let's go find out. Layer one: the Kubernetes API.

---

## Phase 6 — Layer 1: The Kubernetes API (10:00 – 12:30)

[10:00]

Layer 1 is what most people ever see, and it's important to know exactly what it is: an after-action report.

[10:10 — show terminal]

```bash
kubectl describe pod -n shopnow $POD
```

[10:15 — highlight output]

```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
  Started:      ...
  Finished:     ...
Restart Count:  1
```

[10:30]

Kubernetes is telling us: the previous container terminated, the reason was OOMKilled, exit code 137, and here's exactly when it started and when it finished.

[10:42]

We can get the same thing as structured JSON — and I want you to see this because it's the exact field your monitoring and your automation read:

[10:50 — show terminal]

```bash
kubectl get pod -n shopnow $POD -o jsonpath='{.status.containerStatuses[0].lastState}' | python3 -m json.tool
```

```json
{
    "terminated": {
        "exitCode": 137,
        "reason": "OOMKilled",
        "containerID": "containerd://abc123..."
    }
}
```

[11:15]

Notice what's NOT here. There's no "killedBy" field. There's no component taking responsibility. Kubernetes is a witness, not the killer. It watched the container die and wrote down what it observed.

[11:35]

Here's the analogy I want you to keep: kubectl describe is the police report. It tells you the victim's name, time of death, and cause — as best the witness understands it. It does NOT tell you who pulled the trigger. For that, we need to go to the crime scene. The node.

[12:00]

But before we SSH anywhere — there's a number in that report we haven't decoded. Exit code 137. And that number is going to tell us something very specific about the weapon used.

---

## Phase 7 — Decode Exit Code 137 (12:30 – 14:00)

[12:30]

Exit code 137. People see this and think "Kubernetes error 137" or they just shrug. But exit codes have a grammar, and this one is a confession.

[12:45]

The rule: in Linux, an exit code of 128 or higher means the process didn't return — it was KILLED BY A SIGNAL. And the signal number is the exit code minus 128.

[13:00 — show graphic]

```
137 = 128 + 9
       |     |
       |     +-- signal 9 = SIGKILL
       |
       +-- "killed by a signal"
```

[13:15]

Signal 9. SIGKILL. The one signal in Unix that cannot be caught, cannot be blocked, and cannot be ignored. The kernel doesn't ask the process to die. It doesn't even TELL the process it's about to die. The process simply ceases — between two instructions — with no chance to run cleanup, flush buffers, or write a final log line.

[13:40]

That's why the application logs show NOTHING. No exception, no shutdown hook — the process never got the opportunity to say anything. Empty logs plus exit code 137 is the fingerprint of SIGKILL.

[13:55]

So the weapon was SIGKILL. Who fires SIGKILL at processes that use too much memory? The kernel's OOM killer. But we don't take that on faith — we go find the evidence. Layer 2: the container runtime.

---

## Phase 8 — Layer 2: The Container Runtime (14:00 – 16:00)

[14:00]

Everything below this line happens ON THE NODE. So:

[14:05 — show terminal]

```bash
ssh $NODE
```

[14:10]

We're now on k8s-uth-2, the node running our pod. This is where containerd lives — the container runtime that actually created our container's namespaces and cgroups. Kubernetes said "run this." containerd did the work. So containerd saw the raw event.

[14:35]

On K3s, the tool to talk to containerd is crictl. First — all containers, including dead ones:

[14:45 — show terminal]

```bash
sudo crictl ps -a | grep payment-service
```

```
CONTAINER   IMAGE              STATE     NAME
9f3c...     python:3.12-slim   Exited    payment-service
a1b2...     python:3.12-slim   Running   payment-service
```

[15:05]

Two payment-service containers. One exited — that's our victim. One running — the replacement Kubernetes started. Let's inspect the dead one:

[15:20 — show terminal]

```bash
CID=$(sudo crictl ps -a -q --name payment-service | tail -1)
sudo crictl inspect $CID | grep -A5 '"exitCode"'
```

```json
"exitCode": 137,
"reason": "OOMKilled",
```

[15:40]

The runtime confirms it: exit code 137, reason OOMKilled. Now, is this new information? Strictly, no — same facts as Layer 1. But here's why it matters: we're one layer closer to the metal, and this layer didn't hear it from Kubernetes. containerd spawned that process itself. This is the parent reporting how the child died.

[16:05]

One caveat you'll hit in real life: the runtime garbage-collects dead containers fairly quickly. Kubernetes keeps the story longer. That's exactly why you start at Layer 1.

[16:20]

Alright. The runtime told us HOW it died. Now let's find WHERE the rule that killed it lives. Layer 3: cgroups. This is where it gets really good.

---

## Phase 9 — Layer 3: Cgroups — Where the Limit Lives (16:00 – 19:00)

[16:00]

Everything in this layer happens in `/sys/fs/cgroup` — a magic filesystem the kernel exposes. Files you can `cat`, that the kernel reads live. Your memory limit is a FILE. Let's find it.

[16:20 — show terminal]

```bash
CID=$(sudo crictl ps -q --name payment-service)
CGROUP=$(sudo crictl inspect $CID | jq -r .info.runtimeSpec.cgroupsPath)
echo $CGROUP
```

[16:40]

That's our container's cgroup path. Now, three files in that directory tell the entire story.

[16:48 — show terminal]

```bash
echo "memory.max:";     cat $CGROUP/memory.max
echo "memory.current:"; cat $CGROUP/memory.current
echo "memory.events:";  cat $CGROUP/memory.events
```

```
memory.max:      134217728
memory.current:  23592960
memory.events:
  low 0
  high 0
  max 0
  oom 1
  oom_kill 1
  oom_group 0
```

[17:20]

File one: memory.max. One hundred thirty-four million bytes. Our 128Mi limit. This is the YAML you typed, as a kernel-enforced rule. This file has been here since container start — we even read it from inside the container earlier.

[17:40]

File two: memory.current. Twenty-three megabytes — because this is the NEW container, fresh after the restart. In the moment before the kill, this number was past the limit.

[17:55]

File three is the one I want you to burn into memory: memory.events. Look at the last two meaningful lines: `oom 1` — the kernel attempted an OOM kill in this cgroup. And `oom_kill 1` — the kernel COMPLETED a kill here.

[18:20]

This file is the smoking gun. No interpretation needed, no he-said-she-said. This is the kernel's own counter, incrementing the moment it killed a process inside this cgroup. Kubernetes never touches this file. Your application can't write to it. This is the kernel saying: it happened HERE.

[18:45]

So we know where. We know the rule that was broken. But we still haven't seen the killer actually swing. For that, we go to the kernel's own log. Layer 4 — and this is my favorite part of the whole episode.

---

## Phase 10 — Layer 4: The Kernel's Own Log (19:00 – 22:00)

[19:00]

The kernel writes a ring buffer of messages — the thing you read with dmesg. And when the OOM killer strikes, it writes its own confession. Let's find it:

[19:15 — show terminal]

```bash
sudo dmesg -T | grep -i -A5 "out of memory"
```

[19:25 — highlight output]

```
[...] Out of memory: Killed process 18734 (python) total-vm:1234567kB, ...
[...] oom_reaper: reaped process 18734 (python), now anon-rss:0kB, ...
```

[19:40]

Read that first line with me. "Out of memory: Killed process 18734, python." THE KERNEL. NAMED. THE PROCESS. It tells you the PID, the process name, and in the full output — the memory it was holding when it died.

[20:00]

This is the executioner's log. Not a summary written afterward by Kubernetes. Not a report from the runtime. The kernel, in real time, recording its own decision to kill.

[20:20]

So let's assemble the full chain of events, because now we can tell the whole story:

[20:28 — show chain diagram]

```
1. Container allocates memory (our /allocate?mb=200)
2. Kernel: "memory.current would exceed memory.max"  (cgroup rule)
3. Kernel invokes the OOM killer for THIS cgroup
4. OOM killer picks the biggest process in the cgroup (our python — the only one)
5. SIGKILL — instant, uncatchable
6. oom_reaper frees the memory
7. containerd notices the process died: exit code 137
8. Kubernetes notices the container died: "OOMKilled"
9. Kubernetes starts a replacement: restartCount +1
```

[21:15]

Every layer we visited is in that chain, in order. Kubernetes at the END — writing the report. The kernel in the MIDDLE — pulling the trigger. And the cgroup file — memory.max — the rule that started it all, written there at container start by containerd, on Kubernetes' instructions.

[21:40]

One important side note before we leave the kernel. There are TWO OOM killers in a Kubernetes node. What we just watched is the CGROUP OOM killer — it enforces YOUR limit, and only ever considers processes inside that one cgroup. That's what "OOMKilled" means. There's also the NODE-level OOM killer — for when the whole machine is out of memory — and that one is a different beast, with QoS classes and evictions and a completely different set of victims. That's Episode 2, and trust me, the difference matters a LOT.

[22:00]

We have the killer, the weapon, and the motive. There's one more layer — the one that lets you see the crime happen over time, not just after the fact. Metrics.

---

## Phase 11 — Layer 5: Metrics — Watching It Happen (22:00 – 25:00)

[22:00]

Everything so far was forensics — investigating AFTER the death. Metrics let you watch the crime in progress, and catch the next one before it happens. Back on the workstation:

[22:15 — show terminal]

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
```

[22:25]

Three queries tell the whole story. Query one — the cliff. Working set versus limit:

[22:35 — show Prometheus]

```promql
container_memory_working_set_bytes{namespace="shopnow", container="payment-service"}
```

and

```promql
container_spec_memory_limit_bytes{namespace="shopnow", container="payment-service"}
```

[22:55]

Graph them together. The limit is the flat line at 128 megs. The working set climbs — our allocation — hits the ceiling, and drops to the floor. That drop IS the kill. Then a fresh container starts low. Climb, cliff, restart. The sawtooth.

[23:20]

Query two — the Kubernetes verdict, as a metric:

```promql
kube_pod_container_status_last_terminated_reason{namespace="shopnow", reason="OOMKilled"}
```

[23:35]

Flips to one at the moment of the kill. That's kube-state-metrics reading the same field we read at Layer 1, exposing it to Prometheus — which means you can ALERT on it.

[23:50]

And query three is special — it's the kernel's own counter from Layer 3, exposed by cAdvisor:

```promql
increase(container_oom_events_total{namespace="shopnow"}[10m])
```

[24:05]

cAdvisor scrapes the memory.events file — the smoking gun file — and turns it into a time series. You can graph the KERNEL's kill counter from the comfort of Grafana.

[24:20]

If you imported the episode dashboard — five panels: the cliff, percent of limit, the OOMKilled flag, restart counts, and the kernel's kill counter. That dashboard IS this episode, in visual form.

[24:40]

And here's the practical takeaway of this whole layer: the interesting signal isn't the kill — it's the trend BEFORE the kill. Working set at ninety percent of limit for an hour? That's your early warning. The kill itself is just the confirmation.

---

## Phase 12 — Working Set vs RSS vs Virtual Memory (25:00 – 27:00)

[25:00]

One concept to nail down before we wrap, because it trips everyone up: WHICH memory number counts against the limit?

[25:10 — show graphic]

```
Virtual memory:  "I have MAPPED 2 GB"       <- irrelevant
RSS:             "I am TOUCHING 500 MB"     <- close, but includes file cache
Working set:     "I am USING 220 MB"        <- THIS is what the kernel counts
```

[25:35]

Your app can map two gigabytes of virtual address space — the kernel does not care. The kernel charges the WORKING SET — resident memory minus inactive file cache — against memory.max. In Prometheus, that's container_memory_working_set_bytes.

[25:55]

Why the distinction? Because inactive file cache is reclaimable. If the kernel can free up cache to stay under the limit, it will — no kill needed. It's only when the WORKING SET itself crosses the line that the OOM killer wakes up. That reclaim dance is why you sometimes see memory sit AT the limit for a while before dying.

[26:20]

So when someone says "the app only uses 300 megs but the limit is 500 and it still got OOMKilled" — check which number they're reading. If that's virtual, or if it's RSS including cache, the story changes. The working set is the number on trial here. Always.

---

## Phase 13 — QoS Classes, Briefly (27:00 – 28:30)

[27:00]

Real quick — QoS classes, and one nuance that could save you a very confusing afternoon.

[27:10]

Requests equal limits — Guaranteed. Requests less than limits — Burstable, like our pod. Nothing at all — BestEffort. These classes are the priority order for NODE-level memory pressure: when the whole machine is starving, BestEffort dies first, Guaranteed last. That's Episode 2 material.

[27:40]

But here's the nuance: QoS does NOT protect you from a cgroup OOM kill. Our pod is Burstable — didn't matter. You can be GUARANTEED — requests equal limits, top of the priority list — and if your own limit is 128 megs and you allocate 200? Dead. Same SIGKILL, same exit 137. The cgroup limit is enforced regardless of your class.

[28:05]

QoS decides who dies when the NODE is out of memory. Your own limit decides who dies when YOUR CONTAINER is out of memory. Different killers, different rules, different episodes.

---

## Phase 14 — Troubleshooting Checklist (28:30 – 30:00)

[28:30]

Let's turn everything we learned into a repeatable checklist you can run in real incidents.

[28:38 — show checklist]

```
1. kubectl describe pod — OOMKilled? Exit 137? Restarts climbing?
2. How close to the limit is it even when "healthy"? (top / metrics)
3. One-time spike or a leak? — graph working set over 24h/7d
4. Container cgroup or whole node? — check node Memory Pressure
5. What does the app actually need at peak? — compare to limit
6. Fix the cause, set an alert at 90% of limit
```

[29:20]

Step three is the one people skip: the SHAPE of the graph tells you the fix. Steadily climbing even at idle — that's a leak, and no limit size saves you forever. Sawtooth — limit's too low for normal load. Flat with occasional spikes — data-driven: some request or job legitimately needs more.

[29:50]

Three shapes, three different fixes. That one graph is worth ten minutes of guessing.

---

## Phase 15 — Prevention / Best Practices (30:00 – 32:00)

[30:00]

How do we stop meeting like this? Some hard-won rules.

[30:06]

One: right-size limits from MEASURED peak working set — P95, P99 — not guesses, not vibes. Prometheus has your history; use it.

[30:20]

Two: alert at ninety percent of limit. `working set over limit, greater than ninety, for five minutes` — that's your early warning. An OOMKill you predicted is an event. One you didn't is an outage at 2 AM.

[30:40]

Three: watch trends, not points. A slow leak crosses ANY limit eventually. If working set rate-of-change is positive over a week — you have a leak, and the countdown is running.

[30:55]

Four: a limit BELOW your app's normal working set is a guaranteed CrashLoop. I've seen teams set tiny limits to "be safe" — that's not safe, that's a self-inflicted outage loop.

[31:10]

Five: fix leaks at the source. Bigger limits just move the date of the funeral. Profile the app, find what's holding memory, fix it.

[31:25]

And six — the advanced move: for well-understood critical services, consider omitting memory limits entirely and relying on requests plus node capacity. That's a tradeoff with real consequences for node-level pressure, and we'll do it properly in Episode 4. Don't skip ahead and cargo-cult it.

---

## Phase 16 — Cleanup / Outro (32:00 – 33:00)

[32:00]

Everything we did lives in one namespace, so cleanup is one command:

[32:05 — show terminal]

```bash
kubectl delete namespace shopnow
```

[32:12]

The cluster, the monitoring stack — all untouched, ready for the next episode.

[32:20]

Let's close the case one final time. Five layers: Kubernetes — wrote the report. containerd — reported the death. The cgroup — held the rule. The kernel — pulled the trigger. And metrics — recorded it all for history. And the one sentence I want you to remember from all of this:

[32:45]

Kubernetes did NOT kill your pod. It wrote a number in a file and walked away. The kernel did the rest.

[32:55]

Next episode: OOMKilled versus Evicted. They are NOT the same thing — different killers, different layers, different fixes — and confusing them will cost you a very confusing afternoon. Subscribe, and I'll see you there.

---

*End of Narration*
