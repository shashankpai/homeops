# When Logs Kill Servers: Logrotate Explained with a Real Incident
## Full Timestamped Narration

> **Format:** Verbatim spoken narration for all 17 phases.
> **Style:** Conversational, curiosity-driven, progressive discovery.
> **Pattern per troubleshooting step:** SYMPTOM → OBSERVATION → HYPOTHESIS → COMMAND → EVIDENCE → ROOT CAUSE → FIX → VERIFICATION → PREVENTION

---

## Phase 1 — Intro / Hook (0:00 – 1:30)

[0:00]

Imagine this: you get paged at 2 AM. Your application is failing. Users are seeing errors. You log in, check CPU — completely normal. You check memory — totally fine. The application process is running. Everything looks healthy... except users are still getting errors.

[0:20]

So what's going on? You start digging. And then you see this:

[0:25 — show terminal]

```bash
df -h /var/log/myapp
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

[0:35]

The filesystem is 95% full. The application is still running. CPU looks fine. Memory looks fine. But the server is running out of disk. And that's causing the application to fail.

[0:50]

In this episode, we're going to investigate this incident together — exactly like an SRE would during a real on-call. We'll figure out what's consuming all this space, why the application is failing, and how to fix it permanently with a tool called logrotate.

[1:05]

And then — just when you think we're done — I'll show you a surprise. A Linux behavior that catches almost every engineer off guard the first time they see it. We'll delete a huge log file, and the disk space... won't come back. And I'll show you exactly why that happens and how to fix it.

[1:20]

I'm building this on an Ubuntu VM running on Proxmox. Everything we do is on a safe, isolated 500 megabyte filesystem — we're not going to fill up the real root filesystem. Let's get started.

---

## Phase 2 — What Is an Application Log? (1:30 – 3:30)

[1:30]

Before we investigate the incident, let's make sure we understand what an application log actually is. Because here's the thing — logs are not magic. They're just files.

[1:40]

When an application runs, it records information about what it's doing. Every request, every error, every event — it writes a line of text to a file. That file is the log.

[1:50 — show diagram]

```
Application
    |
    | write()
    v
/var/log/myapp/app.log
    |
    v
Disk
```

[2:00]

Let me show you what real log lines look like:

[2:05 — show terminal]

```bash
head -5 /var/log/myapp/app.log
```

```
2026-09-15 10:31:01 INFO request_id=1000 request processed
2026-09-15 10:31:01 INFO request_id=1001 request processed
2026-09-15 10:31:01 ERROR request_id=1002 database timeout
2026-09-15 10:31:01 INFO request_id=1003 request processed
2026-09-15 10:31:01 INFO request_id=1004 request processed
```

[2:20]

Each line has a timestamp, a severity level — INFO or ERROR — a request ID, and a message. This is what most application logs look like.

[2:30]

Now here's the key thing: every single line consumes storage. It's text. It's written to disk. And if the application keeps appending to the same file, that file keeps growing. Forever. Until something stops it.

[2:45]

Think of it like a notebook. Every request adds another page. If nobody ever removes old pages, the notebook eventually becomes huge. That's the problem we're dealing with today.

[3:00]

The application itself may be perfectly healthy. The code is fine. The requests are being processed. The problem isn't the application — it's the lifecycle of the log file. Nobody told the system how to manage the log as it grows. And that's what logrotate is for. But we're getting ahead of ourselves. Let's first reproduce the problem.

---

## Phase 3 — Reproduce Log Growth (3:30 – 6:00)

[3:30]

To make this a realistic incident, I've set up a small demo application that generates log lines continuously. It's a simple bash script that appends realistic log entries to `/var/log/myapp/app.log` in a loop.

[3:45]

Let me start it in the background:

[3:48 — show terminal]

```bash
nohup /usr/local/bin/myapp-loggen.sh > /dev/null 2>&1 &
echo "Log generator PID: $!"
```

```
Log generator PID: 12345
```

[3:55]

Now the "application" is running and generating logs. Let's watch the log file grow:

[4:00 — show terminal]

```bash
ls -lh /var/log/myapp/app.log
```

```
-rw-r--r-- 1 ubuntu ubuntu 1.2M Sep 15 10:31 /var/log/myapp/app.log
```

[4:10]

One point two megabytes. Let's wait a moment and check again:

[4:15 — show terminal]

```bash
ls -lh /var/log/myapp/app.log
```

```
-rw-r--r-- 1 ubuntu ubuntu 15M Sep 15 10:32 /var/log/myapp/app.log
```

[4:22]

Fifteen megabytes. It's growing. Let's check the total directory size:

[4:27 — show terminal]

```bash
du -sh /var/log/myapp
```

```
15M     /var/log/myapp
```

[4:35]

Now, to speed this up for the demo, I'm going to switch to a faster version of the log generator that writes larger log lines with no delay. In a real production system, this would be like an application logging every request with full request details — headers, user IDs, paths, latencies. It adds up fast.

[4:50 — show diagram]

```
10 MB
  ↓
100 MB
  ↓
300 MB
  ↓
450 MB
  ↓
500 MB
  ↓
NO SPACE LEFT ON DEVICE
```

[5:05]

Let's watch the filesystem fill up in real time:

[5:10 — show terminal]

```bash
watch -n 2 'df -h /var/log/myapp && echo "---" && ls -lh /var/log/myapp/app.log'
```

[5:15 — show watch output updating]

```
Every 2.0s: df -h /var/log/myapp && echo "---" && ls -lh /var/log/myapp/app.log

Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  350M  100M  78% /var/log/myapp
---
-rw-r--r-- 1 ubuntu ubuntu 345M Sep 15 10:35 /var/log/myapp/app.log
```

[5:30]

You can see it climbing — 78%, then 85%, then 90%... Let's wait until it gets really close to full.

[5:40 — show final watch output]

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

[5:50]

There we go. 95% full. And the log file is 475 megabytes on a 500 megabyte filesystem. This is our incident. Let's stop watching with Ctrl+C and move on to the investigation.

---

## Phase 4 — Create the Disk-Full Incident (6:00 – 7:30)

[6:00]

So here's our situation. The filesystem is 95% full:

[6:05 — show terminal]

```bash
df -h /var/log/myapp
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

[6:15]

Now, let me show you what happens when the filesystem actually hits 100%. I'll try to write a simple file:

[6:22 — show terminal]

```bash
echo "test write" > /var/log/myapp/test-write.txt
```

```
bash: /var/log/myapp/test-write.txt: No space left on device
```

[6:32]

"No space left on device." That's the error. And here's why this is so dangerous: it doesn't just affect log writing. It affects EVERYTHING that needs disk space.

[6:45]

If your application needs to write a temporary file — it fails. If it needs to write a PID file — it fails. If a database needs to write a transaction — it fails. If an upload needs to be saved — it fails. If the application needs to write cache files, state files, session files — all of it fails.

[7:00]

A storage problem becomes an application outage. The application code might be perfectly healthy, but it can't function because the disk is full. And that's exactly what's happening to our users — they're seeing errors because the application can't perform basic operations.

[7:20]

So now we know the symptom: the filesystem is full. Let's figure out what's consuming all this space.

---

## Phase 5 — Start the Investigation (7:30 – 11:00)

[7:30]

OK, time to investigate like an SRE. We know the filesystem is almost full, but we don't yet know what's consuming it. So let's narrow the search.

[7:40]

The first tool we always reach for is `df`. Let's check all our filesystems:

[7:45 — show terminal]

```bash
df -h
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        20G   8.2G   11G  44% /
tmpfs           2.0G     0  2.0G   0% /dev/shm
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

[8:05]

OK, so we can see the root filesystem at 44% — that's fine. But our demo filesystem at `/var/log/myapp` is at 95%. That confirms where the problem is.

[8:15]

Now, `df` tells us how full the warehouse is. But it doesn't tell us what's inside. For that, we need a different tool. But before we get to that, let me show you something important.

[8:25]

There's actually one more way Linux can report "No space left on device" that you should know about. And it has nothing to do with bytes.

---

### Inode Side-Path (8:30 – 10:00)

[8:30]

Linux filesystems track two different resources. Not one — two.

[8:35 — show diagram]

```
Filesystem
    |
    +-- Storage blocks
    |      └── DATA capacity (how many bytes can be stored)
    |
    +-- Inodes
           └── FILE/OBJECT capacity (how many files can be created)
```

[8:50]

Storage blocks are how much data you can store — that's what `df -h` shows you. Inodes are how many files you can create — that's what `df -i` shows you. Every file, every directory, every symlink needs one inode. And a filesystem can run out of inodes even when it has plenty of free bytes.

[9:10]

Let me show you:

[9:12 — show terminal]

```bash
df -i
```

```
Filesystem      Inodes IUsed IFree IUse% Mounted on
/dev/sda1      1.3M    180K  1.1M   14% /
/dev/loop0      128K     12   128K    1% /var/log/myapp
```

[9:25]

Inodes on our demo filesystem are at 1% — not exhausted. So our problem is bytes, not inodes. Good. But imagine this scenario: you have 20 gigabytes of disk, only 2 gigabytes used, 18 gigabytes free. `df -h` shows plenty of space. But inodes are at 100%. You try to create a new file and you get "No space left on device." That's confusing if you don't know about inodes.

[9:55]

This happens when you have millions of tiny files — session files, cache shards, mail queue entries. It's a real thing that happens in production. But in our case, inodes are fine. The problem is bytes. Let's get back to the main investigation.

---

### Back to Investigation (10:00 – 11:00)

[10:00]

So `df` told us the filesystem is full. Now we need to find out what's consuming the space. `df` tells us how full the warehouse is. `du` tells us which section of the warehouse is using the space.

[10:12 — show terminal]

```bash
sudo du -sh /var/log/myapp
```

```
475M    /var/log/myapp
```

[10:20]

Four hundred seventy-five megabytes — that's almost the entire filesystem. Now let's see what's inside:

[10:27 — show terminal]

```bash
sudo du -ah /var/log/myapp | sort -h
```

```
4.0K    /var/log/myapp
475M    /var/log/myapp/app.log
```

[10:38]

There it is. A single file — `app.log` — is consuming almost all 475 megabytes. Let me cross-reference this with `find`:

[10:48 — show terminal]

```bash
sudo find /var/log/myapp -type f -size +100M -ls
```

```
   12  61440 -rw-r--r--   1 ubuntu ubuntu 475235072 Sep 15 10:35 /var/log/myapp/app.log
```

[11:00]

Confirmed. `app.log` is the single huge file. So to recap: `df` told us the warehouse is full. `du` told us which section is using the space. `find` told us which specific box is huge. And the huge box is our application log.

---

## Phase 6 — Identify the Log as the Root Cause (11:00 – 12:30)

[11:00]

Now we can connect the dots. Let me lay out the full chain:

[11:05 — show diagram]

```
Filesystem nearly full (df -h)
        ↓
/var/log/myapp is consuming most space (du)
        ↓
app.log is huge (find)
        ↓
application keeps appending
        ↓
no effective lifecycle/retention
        ↓
ROOT CAUSE: Uncontrolled log growth
```

[11:30]

The application is doing exactly what it's supposed to do — logging its activity. The problem is that nobody set up a lifecycle for those logs. The log file just keeps growing, and growing, and growing, until it fills the entire filesystem.

[11:45]

This is incredibly common in production. An application gets deployed. It logs its requests. Everything works fine for weeks, or months. And then one day, the disk fills up. Because nobody configured log rotation.

[12:00]

So how do we fix this? We need a tool that manages the lifecycle of log files — one that rotates old logs, compresses them, keeps a sensible number of generations, and deletes the rest. That tool is logrotate. Let me show you how it works.

---

## Phase 7 — Introduce Logrotate (12:30 – 14:30)

[12:30]

OK, let me be really clear about something upfront: logrotate is NOT the application logging system. It doesn't create logs. Your application creates logs. Logrotate manages the lifecycle of logs that already exist.

[12:45 — show diagram]

```
Application
    |
    v
app.log          ← application creates this
    |
    v
logrotate        ← logrotate manages this
    |
    +--> rotate      (rename app.log → app.log.1, start fresh app.log)
    +--> compress    (gzip app.log.1 → app.log.1.gz)
    +--> retain      (keep N generations)
    +--> delete      (remove oldest generation beyond retention limit)
```

[13:10]

Without logrotate, the lifecycle of a log file looks like this: it grows, and grows, and grows, until the disk is full. That's it. There's no lifecycle.

[13:20]

With logrotate, the lifecycle looks like this:

[13:22 — show diagram]

```
app.log
   |
   | rotation (daily or by size)
   v
app.log.1
   |
   | compression
   v
app.log.1.gz
   |
   | retention (keep 7)
   v
eventually deleted (app.log.8.gz is removed)
```

[13:45]

There are four concepts here, and each one is important:

[13:50]

**Rotation.** Logrotate renames the current log file — `app.log` becomes `app.log.1` — and starts a fresh, empty `app.log`. This prevents any single file from growing forever.

[14:05]

**Compression.** The rotated log — `app.log.1` — gets gzipped into `app.log.1.gz`. A 100 megabyte log file typically compresses to 5 or 10 megabytes. That's a 10 to 20x reduction.

[14:20]

**Retention.** Logrotate keeps a configurable number of rotated generations — say, 7. This caps the total disk usage.

[14:28]

**Deletion.** When a new generation is created beyond the retention limit, the oldest one is automatically deleted. Old logs don't accumulate forever.

---

## Phase 8 — Create Logrotate Configuration (14:30 – 17:00)

[14:30]

Let's create a logrotate configuration for our demo application. Logrotate configs live in `/etc/logrotate.d/`, with one file per application.

[14:40 — show terminal]

```bash
sudo tee /etc/logrotate.d/myapp > /dev/null << 'CONFIG'
/var/log/myapp/app.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
CONFIG
```

[15:00]

Let me explain every single directive. Don't worry if you've never seen this before — I'll go through each one.

[15:08]

**`daily`** — This tells logrotate to rotate the log once per day. You can also use `weekly`, `monthly`, or `size 100M` to rotate based on file size instead of time. For a high-volume log, you might want `size 100M` so it rotates as soon as it hits 100 megabytes, regardless of how much time has passed.

[15:30]

**`rotate 7`** — Keep 7 rotated copies before deleting the oldest. With `daily` and `rotate 7`, you keep a week of compressed logs. This is your retention policy. If you need 30 days of logs for compliance, you'd set `rotate 30`.

[15:48]

**`compress`** — Compress rotated logs with gzip. This is the one that saves you the most disk space. A 100 megabyte log compresses to maybe 8 megabytes. Without this, rotation alone barely helps.

[16:05]

**`missingok`** — Don't error if the log file doesn't exist. If the application hasn't created the log yet, or was restarted, logrotate should skip gracefully, not fail. This makes the config robust.

[16:20]

**`notifempty`** — Don't rotate if the log file is empty. No point creating a rotated copy of an empty file.

[16:30]

**`copytruncate`** — This one is important, and we'll dive deeper into it later. Instead of moving the log file and creating a new one, `copytruncate` copies the current log to the rotated name, then truncates the original to zero. The application keeps writing to the same file — no need to signal it to reopen. We'll explain the tradeoffs in detail in Phase 17.

[16:55]

So that's our config. Six directives, and each one serves a specific purpose. Let's test it.

---

## Phase 9 — Demonstrate Logrotate (17:00 – 20:00)

[17:00]

Before we run logrotate for real, let's do a dry run. This is a best practice — always verify before executing.

[17:08 — show terminal]

```bash
sudo logrotate -d /etc/logrotate.d/myapp
```

[17:15 — show output]

```
reading config file /etc/logrotate.d/myapp

Handling 1 log

rotating pattern: /var/log/myapp/app.log  daily (7 rotations)
empty log files are not rotated, old logs are removed
considering log /var/log/myapp/app.log
  log /var/log/myapp/app.log does not need rotating
```

[17:35]

The `-d` flag is debug mode. It tells us what logrotate WOULD do, without actually doing anything. It says "does not need rotating" — that's because the log hasn't reached its rotation threshold yet. It's not a day old. That's expected.

[17:50]

But for the demo, we don't want to wait 24 hours. So let's force a rotation:

[17:55 — show terminal]

```bash
sudo logrotate -f /etc/logrotate.d/myapp
```

[18:02]

The `-f` flag forces rotation immediately. Let's see what happened:

[18:08 — show terminal]

```bash
ls -lh /var/log/myapp/
```

```
-rw-r--r-- 1 ubuntu ubuntu 1.2M Sep 15 10:36 app.log
-rw-r--r-- 1 ubuntu ubuntu  35M Sep 15 10:35 app.log.1.gz
```

[18:25]

Look at that. `app.log` is now small — 1.2 megabytes — because the log generator started writing fresh after truncation. And `app.log.1.gz` is the old content, compressed from 475 megabytes down to 35 megabytes. That's the power of compression.

[18:45]

Let's generate more logs and rotate again:

[18:48 — show terminal]

```bash
sleep 5
sudo logrotate -f /etc/logrotate.d/myapp
ls -lh /var/log/myapp/
```

```
-rw-r--r-- 1 ubuntu ubuntu 2.1M Sep 15 10:37 app.log
-rw-r--r-- 1 ubuntu ubuntu  35M Sep 15 10:36 app.log.1.gz
-rw-r--r-- 1 ubuntu ubuntu  30M Sep 15 10:37 app.log.2.gz
```

[19:10]

Now we have two rotated generations. Let's force several more rotations to see retention in action:

[19:15 — show terminal]

```bash
for i in $(seq 1 8); do
    sleep 2
    sudo logrotate -f /etc/logrotate.d/myapp
done
ls -lh /var/log/myapp/
```

```
-rw-r--r-- 1 ubuntu ubuntu 1.5M Sep 15 10:40 app.log
-rw-r--r-- 1 ubuntu ubuntu  32M Sep 15 10:39 app.log.1.gz
-rw-r--r-- 1 ubuntu ubuntu  30M Sep 15 10:39 app.log.2.gz
-rw-r--r-- 1 ubuntu ubuntu  31M Sep 15 10:39 app.log.3.gz
-rw-r--r-- 1 ubuntu ubuntu  29M Sep 15 10:39 app.log.4.gz
-rw-r--r-- 1 ubuntu ubuntu  33M Sep 15 10:39 app.log.5.gz
-rw-r--r-- 1 ubuntu ubuntu  30M Sep 15 10:39 app.log.6.gz
-rw-r--r-- 1 ubuntu ubuntu  31M Sep 15 10:39 app.log.7.gz
```

[19:50]

Exactly 7 rotated copies — plus the current `app.log`. Older generations were automatically deleted. That's retention working. Let's check the filesystem:

[19:58 — show terminal]

```bash
df -h /var/log/myapp
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  220M  230M  49% /var/log/myapp
```

[20:00]

From 95% down to 49%. The log lifecycle is now bounded. Logrotate is working.

---

## Phase 10 — Demonstrate Bad Retention (20:00 – 22:30)

[20:00]

Now, let me show you what happens when logrotate is configured BADLY. Because here's a common mistake: people think "I have logrotate configured, so I'm fine." But if the config is wrong, you still have the same problem.

[20:15]

Let me replace our good config with a bad one:

[20:18 — show terminal]

```bash
sudo tee /etc/logrotate.d/myapp > /dev/null << 'CONFIG'
/var/log/myapp/app.log {
    daily
    rotate 100
    missingok
    notifempty
    copytruncate
}
CONFIG
```

[20:35]

What's wrong with this? Two things. First, `rotate 100` — keeping 100 generations is way too many for a 500 megabyte filesystem. Second — and this is the big one — there's no `compress`. Rotated logs stay at full size.

[20:55]

Let me clean up and restart the demo:

[21:00 — show terminal]

```bash
pkill -f myapp-loggen 2>/dev/null
sleep 1
rm -f /var/log/myapp/app.log*
nohup /usr/local/bin/myapp-loggen-fast.sh > /dev/null 2>&1 &
sleep 10
```

[21:15]

Now let's rotate several times with the bad config:

[21:18 — show terminal]

```bash
for i in $(seq 1 5); do
    sleep 3
    sudo logrotate -f /etc/logrotate.d/myapp
done
ls -lh /var/log/myapp/
```

```
-rw-r--r-- 1 ubuntu ubuntu 2.0M Sep 15 10:42 app.log
-rw-r--r-- 1 ubuntu ubuntu  90M Sep 15 10:42 app.log.1
-rw-r--r-- 1 ubuntu ubuntu  85M Sep 15 10:42 app.log.2
-rw-r--r-- 1 ubuntu ubuntu  88M Sep 15 10:42 app.log.3
-rw-r--r-- 1 ubuntu ubuntu  82M Sep 15 10:42 app.log.4
-rw-r--r-- 1 ubuntu ubuntu  80M Sep 15 10:42 app.log.5
```

[21:50]

Notice: no `.gz` extension. No compression. Each rotated file is 80 to 90 megabytes. Let's check the filesystem:

[21:58 — show terminal]

```bash
df -h /var/log/myapp
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

[22:10]

95% full again! Rotation alone did NOT solve the problem. The logs are still consuming the same total space — they're just split across multiple files. Without compression and with excessive retention, we've simply moved the problem around.

[22:25]

The lesson is clear: rotation without compression and sensible retention is not a solution. You need all three. Let me restore the good config:

[22:30 — show terminal]

```bash
sudo tee /etc/logrotate.d/myapp > /dev/null << 'CONFIG'
/var/log/myapp/app.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
CONFIG
```

---

## Phase 11 — Who Runs Logrotate? (22:30 – 24:30)

[22:30]

Here's a question that trips up a lot of people: when does logrotate actually run? Does it sit in the background, watching your log files, waiting for them to get big?

[22:42]

No. Logrotate is not a daemon. It doesn't run continuously. It's a batch tool. It runs, does its work, and exits. Something else has to schedule it.

[22:55 — show diagram]

```
systemd timer / cron
        |
        v
    logrotate (runs, does work, exits)
        |
        v
/etc/logrotate.conf (main config)
        |
        +----> /etc/logrotate.d/* (individual app configs)
```

[23:10]

On modern Ubuntu, logrotate is scheduled by a systemd timer. Let me show you:

[23:15 — show terminal]

```bash
systemctl status logrotate.timer
```

```
● logrotate.timer - Daily rotation of log files
     Loaded: loaded (/lib/systemd/system/logrotate.timer; enabled)
     Active: active (waiting) since Tue 2026-09-15 10:00:00 UTC; 30min ago
    Trigger: Wed 2026-09-16 00:00:00 UTC; 13h left
   Triggers: ● logrotate.service
```

[23:40]

It's active, enabled, and triggers daily at midnight. Let me also show the timer list:

[23:45 — show terminal]

```bash
systemctl list-timers | grep logrotate
```

```
NEXT                        LEFT       LAST                        PASSED  UNIT            ACTIVATES
Wed 2026-09-16 00:00:00 UTC 13h left   Tue 2026-09-15 10:00:00 UTC 30min ago logrotate.timer logrotate.service
```

[24:05]

So every day at midnight, systemd starts the logrotate service, which processes all configs in `/etc/logrotate.d/`. Let me show you what's in there:

[24:15 — show terminal]

```bash
ls /etc/logrotate.d/
```

```
alternatives  apt  chrony  dpkg  myapp  rsyslog  ufw
```

[24:25]

Our `myapp` config sits alongside system configs for apt, rsyslog, ufw, and others. Logrotate processes all of them on each run.

[24:30]

Now, on older Ubuntu systems, logrotate might be scheduled via cron instead of a systemd timer — specifically `/etc/cron.daily/logrotate`. The exact mechanism can vary, so check your specific system. But the concept is the same: a scheduler runs logrotate periodically, and logrotate processes all its configs.

---

## Phase 12 — The Surprise: Deleted File But Disk Space Is Still Used (24:30 – 30:40)

[24:30]

OK, now we're getting to what I think is the most interesting part of this episode. This is the surprise that catches almost every engineer the first time they see it.

[24:40]

Let me set the scene. You're on call. The disk is full. You find a huge log file. And you think, "I'll just delete it. Problem solved." So you `rm` the file. And then... the disk space doesn't come back.

[24:58]

Let me show you exactly what I mean. Our log generator is still running, and it's writing to `app.log`. Let me check the current state:

[25:05 — show terminal]

```bash
df -h /var/log/myapp
ls -lh /var/log/myapp/
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  300M  160M  63% /var/log/myapp

total 301M
-rw-r--r-- 1 ubuntu ubuntu 280M Sep 15 10:45 app.log
-rw-r--r-- 1 ubuntu ubuntu  20M  Sep 15 10:44 app.log.1.gz
```

[25:25]

OK, 280 megabytes in `app.log`, filesystem at 63%. Now, let's delete that log file:

[25:32 — show terminal]

```bash
sudo rm /var/log/myapp/app.log
```

[25:38]

Let's verify the file is gone:

[25:40 — show terminal]

```bash
ls -lh /var/log/myapp/
```

```
total 20M
-rw-r--r-- 1 ubuntu ubuntu 20M Sep 15 10:44 app.log.1.gz
```

[25:50]

The file is gone. Not in the directory listing anymore. Now let's check the filesystem:

[25:55 — show terminal]

```bash
df -h /var/log/myapp
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  300M  160M  63% /var/log/myapp
```

[26:10]

Wait. The file is gone. But the disk usage is UNCHANGED. Still 300 megabytes used, still 63%. We just deleted a 280 megabyte file and got zero space back. What is going on?

[26:28]

Here's what's happening. On Linux, deleting a file only removes its directory entry — the name. But if a process still has the file open — through a file descriptor — the kernel keeps the inode and its data blocks alive until that process closes the file.

[26:48 — show diagram]

```
process (myapp-loggen)
   |
   v
file descriptor (still open!)
   |
   v
deleted file (app.log — name removed, but inode + data blocks still exist)
   |
   v
disk blocks still occupied (280 MB still consumed)
```

[27:10]

Think of it like this: the filename is like the label on a storage box. Removing the label does not necessarily mean the person currently using the box has stopped using it. The box — and its contents — stays in the warehouse until the person is done with it.

[27:30]

Our log generator process still has the file open. It's still writing to it. The file is "deleted" from the directory, but the data blocks are still on disk, still occupied, still consuming 280 megabytes.

[27:45]

So how do we find this? How do we find a file that's been deleted but is still held open by a process? This is where `lsof` comes in. Specifically, `lsof +L1`.

[28:00 — show terminal]

```bash
sudo lsof +L1
```

```
COMMAND      PID    USER   FD   TYPE  SIZE/OFF NLINK  NODE NAME
myapp-logge 12350 ubuntu   3w   REG   280M    0   12345 /var/log/myapp/app.log (deleted)
```

[28:20]

Let me break down what we're seeing. `lsof` lists open files. The `+L1` flag is the key — it filters for files with a link count less than 1. A link count of 0 means the file has been unlinked — deleted from the directory — but it still has an open file descriptor.

[28:40]

So we can see: the command is `myapp-logge` — our log generator. The PID is 12350. The file descriptor is `3w` — descriptor 3, opened for writing. The size is 280 megabytes. The link count is 0. And the name says `/var/log/myapp/app.log (deleted)` — confirmed, it's our deleted log file.

[29:05]

Now, how do we actually get the space back? The space is released when the process closes the file descriptor. That happens when the process exits, or when it closes the file, or when it reopens the log, or when it's restarted.

[29:20]

But here's the thing — in production, you might not want to restart the process. You might not be able to afford the downtime. So there's a trick. You can truncate the file through its file descriptor in `/proc`, which frees the disk blocks immediately while keeping the process running.

[29:40]

Let me find the file descriptor:

[29:42 — show terminal]

```bash
LOGGEN_PID=$(pgrep -f myapp-loggen)
ls -la /proc/$LOGGEN_PID/fd/ | grep deleted
```

```
l-wx------ 1 ubuntu ubuntu 64 Sep 15 10:46 3 -> /var/log/myapp/app.log (deleted)
```

[30:00]

Descriptor 3. Now let me truncate it:

[30:02 — show terminal]

```bash
sudo sh -c ': > /proc/'$LOGGEN_PID'/fd/3'
```

[30:10]

Let's check the filesystem:

[30:12 — show terminal]

```bash
df -h /var/log/myapp
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M   21M  430M   5% /var/log/myapp
```

[30:25]

280 megabytes reclaimed. The process is still running. No restart needed. That's the power of understanding what's happening at the file descriptor level.

[30:35]

But the real lesson here is: don't just `rm` a log file that a process is writing to. Use logrotate with `copytruncate`, or use `postrotate` to signal the application to reopen its log. Or, if you need to free space manually, truncate the file in place with `: > /var/log/myapp/app.log` — that empties the file without deleting it, so the process keeps writing normally.

---

## Phase 13 — copytruncate Deep Dive (30:40 – 33:30)

[30:40]

OK, let's talk about `copytruncate` in more detail. Because it's the directive we used in our config, and it has an interesting tradeoff.

[30:50]

To understand why `copytruncate` exists, let's look at what happens WITHOUT it. When logrotate rotates a log normally, it moves `app.log` to `app.log.1` and creates a new empty `app.log`. But here's the problem: the application still has its file descriptor pointing to the old inode — the one that's now called `app.log.1`. The application keeps writing to the rotated file, not the new `app.log`.

[31:00 — show diagram]

```
Without copytruncate:

Application writes to fd → app.log (inode 100)
                             |
                             | logrotate MOVES the file
                             v
                          app.log.1 (inode 100)  ← app still writes here!
                          app.log (inode 200)    ← new empty file, app NOT writing here
```

[31:15]

So without `copytruncate`, you need to tell the application to close its old file descriptor and open a new one. That's what `postrotate` scripts do — they send a signal to the application, and the application reopens its log file. We'll see this with Nginx in the next section.

[31:35]

With `copytruncate`, logrotate takes a different approach. It copies the contents of `app.log` to `app.log.1`, then truncates `app.log` to zero — in place, same inode. The application's file descriptor still points to the same inode. The file is now empty, and the application continues writing from the beginning.

[31:55 — show diagram]

```
With copytruncate:

Application writes to fd → app.log (inode 100)
                             |
                             | logrotate COPIES content to app.log.1
                             | logrotate TRUNCATES app.log to 0 bytes
                             v
                          app.log (inode 100, now empty)  ← app still writes here, same fd!
                          app.log.1 (copy of old content)
```

[32:20]

The advantage is obvious: no need to signal the application. It works with any application, even ones that don't support log reopening. The application doesn't even know rotation happened.

[32:35]

But there's a tradeoff. Between the copy and the truncate, there's a small race window. Any log lines written by the application during that brief moment may end up in the copy — `app.log.1` — AND be lost when the original is truncated. In practice, this window is milliseconds, and for most applications, losing a few log lines during rotation is acceptable. But for high-throughput or audit-critical logging, this tradeoff might not be acceptable.

[33:05]

So don't think of `copytruncate` as universally the best option. It's a pragmatic choice for applications that don't support log reopening. For applications that do — like Nginx — there's a cleaner approach. Let me show you.

---

## Phase 14 — Production-Style Log Reopen with Nginx + Live Demo (33:30 – 37:00)

[33:30]

For production applications that support it, the preferred model is: rotate the log, then signal the application to reopen its log files. Let me show you how this works with Nginx, which is one of the most common production web servers.

[33:45]

Here's a representative Nginx logrotate config:

[33:48 — show terminal]

```bash
cat /etc/logrotate.d/nginx 2>/dev/null || echo "Showing representative config:"
```

```
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}
```

[34:15]

The key part is the `postrotate` section. After logrotate rotates the log — moves `app.log` to `app.log.1` and creates a new `app.log` — it runs this script. The script sends the USR1 signal to the Nginx master process.

[34:35]

When Nginx receives USR1, it reopens its log files. It closes the old file descriptor — the one pointing to what is now `app.log.1` — and opens a new file descriptor to the fresh `app.log`. From that point on, Nginx writes to the new log file.

[34:55 — show diagram]

```
1. logrotate runs
2. app.log → app.log.1 (moved)
3. New empty app.log created
4. postrotate: kill -USR1 <nginx_pid>
5. Nginx receives USR1
6. Nginx closes old fd (was pointing to app.log.1)
7. Nginx opens new fd to app.log
8. Nginx continues writing to new app.log
```

[35:20]

Let me also explain `delaycompress`. This directive delays compression by one rotation cycle. The most recently rotated file — `app.log.1` — is not compressed immediately. This matters because the application might still have its file descriptor open to `app.log.1` for a brief moment during the postrotate signal. Compressing a file that's still being written to could cause issues. With `delaycompress`, `app.log.1` stays uncompressed, and it gets compressed on the next rotation when it becomes `app.log.2.gz`.

[35:50]

Now, I don't have Nginx installed on this VM, and we don't need it. We can see this exact mechanism live with our demo app. I've created a signal-aware version of the log generator that reopens its log file when it receives SIGHUP — same concept, just a different signal than Nginx's USR1.

[36:00 — show terminal]

Let me start the signal-aware app and write its PID to the file where the postrotate script expects to find it:

```bash
pkill -f myapp-loggen 2>/dev/null
sleep 2
rm -f /var/log/myapp/app.log*

nohup /usr/local/bin/myapp-loggen-reopen.sh > /dev/null 2>&1 &
REOPEN_PID=$!
echo $REOPEN_PID | sudo tee /var/run/myapp-reopen.pid > /dev/null
echo "Signal-aware log generator PID: $REOPEN_PID"
sleep 3
tail -3 /var/log/myapp/app.log
```

[36:15]

Good — the app is running and writing logs. Now let me force a rotation with the postrotate config:

```bash
sudo logrotate -f /etc/logrotate.d/myapp-reopen
```

[36:25]

Let's see what happened:

```bash
ls -lh /var/log/myapp/
echo "--- New app.log ---"
tail -5 /var/log/myapp/app.log
echo "--- app.log.1 ---"
tail -5 /var/log/myapp/app.log.1
```

[36:35]

Look at that. `app.log.1` has the old log lines — from before rotation. And `app.log` has the "log reopened after SIGHUP" marker, followed by brand new log lines. The app caught the signal, closed its old file descriptor, and opened a new one pointing to the fresh `app.log`. No log lines were lost.

[36:50]

Now let me show you what happens WITHOUT the signal — the problem this solves. I'll switch back to our original app that does NOT handle signals, and rotate again:

```bash
pkill -f myapp-loggen-reopen 2>/dev/null
sleep 2
rm -f /var/log/myapp/app.log*
nohup /usr/local/bin/myapp-loggen-fast.sh > /dev/null 2>&1 &
sleep 3
sudo logrotate -f /etc/logrotate.d/myapp-reopen
sleep 2
echo "--- app.log (EMPTY — app not writing here) ---"
ls -lh /var/log/myapp/app.log
echo "--- app.log.1 (app STILL writing here!) ---"
tail -3 /var/log/myapp/app.log.1
```

[37:00]

See that? `app.log` is empty — zero bytes. The app is NOT writing to it. And `app.log.1` is still growing — the app is still writing to the old file descriptor, which now points to the rotated file. The postrotate script sent SIGHUP, but the original app doesn't handle it, so it just ignored the signal.

This is exactly the problem that `copytruncate` solves differently — by truncating in place instead of moving and signaling. And it's exactly why production apps like Nginx support log reopening. Rotate plus signal equals clean. No race window, no extra copy, no lost log lines.

---

## Phase 15 — Real Incident Troubleshooting Checklist (37:00 – 39:00)

[37:00]

Let me put together the complete troubleshooting flow we've been following. This is the checklist you'd use during a real disk-full incident.

[37:10 — show diagram]

```
DISK ALERT
   |
   v
df -h
   |
   +--> Is storage exhausted? (bytes)
   |
   v
df -i
   |
   +--> Are inodes exhausted? (file slots)
   |
   v
du (find which directories use the space)
   |
   v
find (identify specific large files)
   |
   v
Is it a log?
   |
   +---- YES ---> inspect logrotate config
   |
   +---- NO ----> investigate other consumers
   |
   v
lsof +L1
   |
   +--> deleted-but-open files holding space?
   |
   v
fix / rotate / reopen / clean retention
   |
   v
verify df -h
   |
   v
PREVENTION
```

[38:00]

Step one: you get a disk alert. Run `df -h`. Is storage exhausted? Then run `df -i`. Are inodes exhausted? This is a quick check — it takes two seconds and it rules out half the possible causes.

[38:20]

Step two: run `du` to find which directories are using the space. Then run `find` to identify the specific large files.

[38:30]

Step three: is the large file a log? If yes, inspect the logrotate config. Is rotation configured? Is compression enabled? Is retention sensible? Is the scheduler running?

[38:45]

If it's not a log, investigate other consumers — core dumps, temp files, package caches, docker images.

[38:55]

Step four: run `lsof +L1` to check for deleted-but-open files holding space. Fix the issue — rotate, reopen, clean retention. Verify with `df -h`. And then — prevention.

---

## Phase 16 — Prevention (39:00 – 41:30)

[39:00]

The best incident is the one that never happens. So let's talk about prevention.

[39:05]

First: every application that writes logs should have a logrotate config. Review it, test it, and make sure it actually works. I can't tell you how many times I've seen a logrotate config that looks correct but has a typo or a wrong path and has never actually rotated anything.

[39:25]

Second: always enable compression. A 100 megabyte log compresses to maybe 8 megabytes. That's a 12x reduction. There's almost no reason not to compress.

[39:40]

Third: set retention based on your disk capacity and operational needs. Don't keep 100 generations on a 500 megabyte filesystem. And don't keep 7 generations if you need 30 days of logs for compliance.

[39:55]

Fourth: for applications that support it, use `postrotate` with a signal instead of `copytruncate`. Nginx, Apache, rsyslog — they all support log reopening. It's cleaner, no race window.

[40:10]

Fifth: monitor disk usage. Don't wait for 100%. Set alerts at 80% and 90%. Investigate at 80%, act at 90%. A filesystem should never hit 100% in production.

[40:25]

Sixth: consider centralized logging. For large fleets, forwarding logs to a centralized system — like ELK, Loki, or Grafana — reduces local disk pressure and enables cross-host search. You still need local logrotate for the local copies, but the retention pressure is much lower.

[40:45]

Seventh: for containers, Docker and other runtimes have their own logging mechanisms. Container logs should not be treated exactly like traditional host log files. Use `docker logs` and configure log driver rotation — for example, `--log-opt max-size=10m --log-opt max-file=3`.

[41:05]

Eighth: use configuration management — Ansible, Puppet, Chef — to deploy logrotate configs consistently across your fleet. Don't manually edit `/etc/logrotate.d/` on individual servers. That's how you get drift.

[41:20]

And ninth: review log volume after application changes. A new debug log line can 10x your log output overnight. After deploying a new version, check if log volume has changed.

[41:30]

The golden rule is this: the goal is not simply "delete logs." The goal is to establish a predictable log lifecycle. Logs are created, rotated, compressed, retained for a defined period, and then automatically deleted. No manual intervention needed.

---

## Phase 17 — Cleanup / Reset (41:30 – 43:00)

[41:30]

Alright, let's clean up the demo so your VM is back to its original state. I'll warn you — these next commands are destructive, so don't run them unless you're done with the demo.

[41:42 — show terminal]

```bash
# Stop the log generator
pkill -f myapp-loggen 2>/dev/null
sleep 2

# Remove the logrotate configs
sudo rm -f /etc/logrotate.d/myapp
sudo rm -f /etc/logrotate.d/myapp-reopen

# Unmount the demo filesystem
sudo umount /var/log/myapp

# Detach the loop device
sudo losetup -d /dev/loop0 2>/dev/null || true

# Remove the backing image file
sudo rm -f /tmp/myapp-fs.img

# Remove the demo directory
sudo rm -rf /var/log/myapp

# Remove the demo scripts and PID file
sudo rm -f /usr/local/bin/myapp-loggen.sh
sudo rm -f /usr/local/bin/myapp-loggen-fast.sh
sudo rm -f /usr/local/bin/myapp-loggen-reopen.sh
sudo rm -f /var/run/myapp-reopen.pid
```

[42:30]

And let me verify everything is cleaned up:

[42:32 — show terminal]

```bash
mount | grep myapp || echo "No myapp mount (good)"
ls -la /tmp/myapp-fs.img 2>/dev/null || echo "Image file removed (good)"
ls -la /etc/logrotate.d/myapp 2>/dev/null || echo "Logrotate config removed (good)"
ls -la /etc/logrotate.d/myapp-reopen 2>/dev/null || echo "Reopen config removed (good)"
df -h /
```

```
No myapp mount (good)
Image file removed (good)
Logrotate config removed (good)
Reopen config removed (good)
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        20G   8.2G   11G  44% /
```

[43:00]

Everything is cleaned up. The VM is back to its original state.

---

## Outro (43:00 – 44:00)

[43:00]

So let's recap what we covered today.

[43:05]

We started with a production incident: the filesystem was full, the application was failing, and we didn't know why. We used `df` to confirm the filesystem was full, `du` to find which directory was consuming the space, and `find` to identify the specific large file — our application log.

[43:25]

We learned that logrotate manages the lifecycle of logs — rotating, compressing, retaining, and deleting them. We configured it, tested it, and saw disk usage drop from 95% to 49%.

[43:40]

We saw what happens with a bad config — rotation without compression and with excessive retention just moves the problem around.

[43:50]

We saw the log reopen mechanism live — how a signal-aware app closes its old file descriptor and opens a new one after rotation, just like Nginx does in production.

[44:00]

And then we hit the surprise: deleting a log file doesn't free disk space if a process still has it open. We found the deleted-but-open file with `lsof +L1` and reclaimed the space by truncating through `/proc`.

If this was helpful, subscribe for more practical Linux and SRE troubleshooting episodes. In the next one, we'll tackle another real production incident. See you then.

---

*End of Narration*
