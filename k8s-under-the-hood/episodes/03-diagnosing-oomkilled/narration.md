# How do you actually diagnose an OOMKilled Pod?
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for 9 phases (~16 minutes).
> **Style:** One fresh kill, investigated start-to-finish with a repeatable
> runbook. The methodology episode — the one viewers bookmark.
> **Pattern:** SYMPTOM → TRIAGE → (one layer deeper than needed) → STOP.

---

## Phase 1 — Hook: The 5-Minute Version (0:00 – 1:00)

[0:00]

It's 9am. A pod restarted overnight. Someone asks you in the standup: "what happened to the payment service?" You have about five minutes before that meeting. Where do you look FIRST?

[0:15]

Here's the honest truth about debugging in production: you don't have time to descend through five layers like we did in Episode 1. You need a runbook. An ORDER. A way to know, in thirty seconds, which family of death you're dealing with — and exactly how deep you need to go for the answer. No deeper.

[0:45]

In this episode we build that runbook the only way it sticks — by using it. Fresh kill. Timer running.

---

## Phase 2 — Triage: The 30-Second Fork (1:00 – 3:00)

[1:00]

Before logs, before describe, before anything — this one command. Get the pods, with the right columns:

[1:08 — show terminal]

```bash
kubectl get pods -A -o custom-columns=\
NS:.metadata.name,POD:.metadata.name,STATUS:.status.phase,\
RESTARTS:.status.containerStatuses[0].restartCount,\
LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason,\
WAITING-REASON:.status.containerStatuses[0].state.waiting.reason
```

[1:35]

And here's our crime scene — I've staged two broken pods on purpose. payment-service: RESTARTS climbing, LAST-REASON, OOMKilled. And next to it, crashy: WAITING-REASON, CrashLoopBackOff.

[2:00]

Two pods. Both "broken." Three possible families:

[2:05 — show diagram]

```
LAST-REASON: OOMKilled         -> container crossed its limit  -> KERNEL
WAITING-REASON: CrashLoopBackOff -> app fails to start          -> THE APP
STATUS: Failed, Reason: Evicted  -> node pressure               -> KUBELET
```

[2:30]

Thirty seconds, and you already know which investigation to run — or better, that you DON'T need one. The CrashLoop pod? Its logs will literally tell you the answer. The OOMKilled pod? Its logs will tell you nothing. Which brings me to the trap.

---

## Phase 3 — The False Leads (3:00 – 4:30)

[3:00]

Every instinct says: check the logs. So let's check the logs.

[3:06 — show terminal]

```bash
kubectl logs -n shopnow $POD --previous
```

[3:15]

No exception. No stack trace. Not even a goodbye. If you're lucky, you get the startup banner from two days ago. People burn hours here — grepping, re-deploying, adding logging — because empty logs FEEL like missing evidence. They're not. They're the evidence.

[3:45]

SIGKILL cannot be caught, cannot be handled, cannot be logged. The process died between two write calls to stdout. Empty logs on a dead pod isn't a dead end — it's a hint that points straight at an OOMKill.

[4:00 — show terminal]

Now the other pod:

```bash
kubectl logs -n crashloop-demo crashy --previous
```

```
starting up... connecting to dependency... FAILED: exit 1
```

[4:15]

Complete opposite. The CrashLoop pod's logs TELL you the answer — it's an app problem, look at the app. Same pod list, same "broken" status, opposite debugging paths. That's why triage comes before logs, and not the other way around.

---

## Phase 4 — Layer 1: The API (4:30 – 7:00)

[4:30]

Family confirmed: OOMKilled. Now the after-action report.

[4:36 — show terminal]

```bash
kubectl describe pod -n shopnow $POD
```

[4:45]

Everything you need is in one block: Last State Terminated, Reason OOMKilled, Exit Code 137, Restart Count. And let's decode that exit code properly, because it's not a magic number:

[5:05 — show diagram]

```
Exit Code 137  =  128 + 9
   128 = "this process was killed by a signal"
     9 = SIGKILL — uncatchable, unignorable
```

[5:25]

128-plus-9. And only two things send SIGKILL to a container: the kernel's OOM killer, or the kubelet killing a failing liveness probe. The LAST-REASON field just told you which one. OOMKilled means kernel. If it said something else with a 137 — probe the kubelet path. The exit code is a fork with exactly two branches.

[5:55]

Stop-check. If the standup question was "what happened?" — you're done. Kernel killed it, it crossed the limit, exit 137. You can walk into that meeting with the answer. The only reason to go deeper is if you need to answer a harder question: was this a leak, or is the pod just under-sized? Because that question decides the fix. And for THAT, we need metrics.

---

## Phase 5 — Layer 2: Metrics — The Fix Decider (7:00 – 9:30)

[7:00]

This is the layer I call the fix decider, and it's three queries.

[7:06 — show terminal]

```promql
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
```

[7:15]

One — confirm the verdict from metrics. Same answer as describe, but this one works even when the pod is already gone and recreated.

[7:28 — show Grafana]

Two — the autopsy graph. Working set versus limit, in the minutes before death. The climb. The ceiling. The cliff. Now read it like a diagnostician: how long was the runway? How close did it get before the end?

[7:55]

Three — the shape of the climb. And this is the single most useful query in this episode:

[8:00 — show terminal]

```promql
deriv(container_memory_working_set_bytes[10m])
```

[8:10]

The rate of growth, bytes per second. And here's the diagnostic: a LEAK climbs linearly and never flattens — the derivative stays positive forever. A legit cache warms up and plateaus — the derivative falls back to zero.

[8:40]

Linear climb: leak. Fix the application. Plateau above the limit: under-sized. Right-size the pod. Step change right at a deploy: regression. Rollback.

[8:55]

One query, three shapes, three different fixes. If you take exactly one thing from this episode into your next incident, make it this one. And notice what we did NOT need for any of it — we never SSH'd anywhere. The stop rule in action.

---

## Phase 6 — Layer 3: The Node, When It's Contested (9:30 – 11:30)

[9:30]

Sometimes metrics aren't enough. The pod's been recreated so the history is gone. Or someone — a vendor, a teammate — says "are you SURE it was an OOMKill?" For that, the kernel's own counter.

[9:50 — show terminal]

```bash
POD_UID=$(kubectl get pod -n shopnow $POD -o jsonpath='{.metadata.uid}')
NODE=$(kubectl get pod -n shopnow $POD -o jsonpath='{.spec.nodeName}')
CG=/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod${POD_UID//-/_}.slice
ssh -i lab/ssh/id_rsa ubuntu@$NODE "cat $CG/memory.events"
```

[10:15]

The pod's cgroup. And there it is — oom underscore kill, and a positive number. That counter is incremented by the kernel, in the kernel's own data structure. Nobody else writes to it. It survives container restarts. It is the closest thing to a signed confession you will get from a Linux kernel.

[10:50]

Use this layer when the answer is contested or the pod view has evaporated. But notice — we're now two minutes and one SSH session deep. That's the price of proof. Which is why the runbook has a stop rule for every layer.

---

## Phase 7 — Layer 4: dmesg, and the Stop Rule (11:30 – 13:00)

[11:30]

The deepest layer — the kernel's kill log:

[11:36 — show terminal]

```bash
ssh -i lab/ssh/id_rsa ubuntu@$NODE "sudo dmesg -T | grep -i -E 'out of memory|killed process'"
```

[11:45]

Timestamp, PID, process name, the OOM score of the victim — the kill record itself. This is exhibit A material: post-mortems, vendor escalations, "prove it" moments.

[12:00]

But if you're reading dmesg during an active incident just to satisfy curiosity — you're procrastinating, in a very technical costume. So here's the stop rule, and this is the runbook's soul:

[12:15 — show diagram]

```
You need to say...            Stop at...
"It OOMKilled"                Layer 1 (API)
"It's a leak / under-sized"    Layer 2 (metrics)
"Prove the kernel did it"      Layer 3 (memory.events)
"Exhibit A for the postmortem" Layer 4 (dmesg)
```

[12:45]

Investigate one layer deeper than you need. Never five.

---

## Phase 8 — The Evidence Matrix (13:00 – 14:30)

[13:00]

Let's assemble the whole runbook into one table — this is the screenshot.

[13:05 — show full-frame table]

| Layer | Command | Answers | Cost |
|---|---|---|---|
| Triage | `kubectl get pods` (custom cols) | which family of death | 5s |
| Logs | `kubectl logs --previous` | CrashLoop only; EMPTY = OOM hint | 10s |
| 1 API | `kubectl describe pod` | who, why, exit 137 | 10s |
| 2 Metrics | WS/limit, `deriv()` | leak vs under-sized | 60s |
| 3 Node | `cat memory.events` | kernel's signed confession | 2min |
| 4 Kernel | `dmesg` | the kill itself, timestamped | 2min |

[13:45]

Every row is something we ran live in the last ten minutes. Nothing theoretical. The printable version with all the exact commands is in the repo — runbook.md, linked below.

[14:00]

And the payoff of the whole discipline: when someone asks "what happened to the payment service?", you don't guess. You say: "Kernel killed it at 3:14am, container crossed its 128-meg limit, exit 137, working set was climbing linearly for six hours — it's a leak, and here's the trend graph." Forty-five seconds, every claim evidenced. That's what a runbook buys you.

---

## Phase 9 — Outro: The Next Question (14:30 – 16:00)

[14:30]

So now you can diagnose an OOMKill at three speeds: the 30-second triage, the 5-minute answer, and the full evidence chain for the post-mortem.

[14:45]

But diagnosis is reactive. The standup question that actually matters is: "what are we doing so it doesn't happen again?" And that's an engineering question with exactly two answers, depending on what the deriv query told you. If it's a leak — fix the app, and DON'T just raise the limit; I'll show you the math on why that only buys time. If it's under-sized — right-size from real data, and put an alert at 90 percent of the limit so the next one pages you before the kernel does.

[15:30]

That's Episode 4 — the season finale: prevention. We take this exact pod, fix it both ways, prove the fix survives the same load that killed it, and wire the alert that fires before the kernel does.

[15:50]

Runbook's in the repo — one command to reproduce all of this. Subscribe if you want the fix. See you in the finale.
