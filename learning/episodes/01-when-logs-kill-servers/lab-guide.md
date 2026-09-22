# When Logs Kill Servers: Logrotate Explained with a Real Incident
## Lab Guide & Runbook

> **Series:** Practical Linux/SRE Troubleshooting
> **Episode:** 01 — When Logs Kill Servers
> **Lab Environment:** Ubuntu Linux VM on Proxmox (local, no cloud, no Kubernetes)
> **Safety:** All destructive work happens on an isolated 500 MB loopback filesystem. The real root filesystem is never touched.

---

## Table of Contents

1. [Episode Overview](#1-episode-overview)
2. [Learning Objectives](#2-learning-objectives)
3. [Final Lab Architecture](#3-final-lab-architecture)
4. [Prerequisites](#4-prerequisites)
5. [Safe Isolated Filesystem Setup](#5-safe-isolated-filesystem-setup)
6. [Demo Application / Log Generator](#6-demo-application--log-generator)
7. [Incident Injection](#7-incident-injection)
8. [Initial Disk Investigation](#8-initial-disk-investigation)
9. [Brief Inode Exhaustion Side-Path](#9-brief-inode-exhaustion-side-path)
10. [Identifying the Large Log](#10-identifying-the-large-log)
11. [Logrotate Explanation](#11-logrotate-explanation)
12. [Logrotate Configuration](#12-logrotate-configuration)
13. [Rotation / Compression / Retention Demo](#13-rotation--compression--retention-demo)
14. [Broken Retention Configuration Demo](#14-broken-retention-configuration-demo)
15. [Logrotate Scheduler Explanation](#15-logrotate-scheduler-explanation)
16. [Deleted-but-Open File Demo](#16-deleted-but-open-file-demo)
17. [copytruncate Deep Dive](#17-copytruncate-deep-dive)
18. [Nginx Production Example (with Live Reopen Demo)](#18-nginx-production-example)
19. [Complete Troubleshooting Checklist](#19-complete-troubleshooting-checklist)
20. [Prevention / Best Practices](#20-prevention--best-practices)
21. [Cleanup / Reset](#21-cleanup--reset)
22. [Hashtags](#22-hashtags)

---

## 1. Episode Overview

This episode is built around a realistic production incident:

> The application is running. CPU is normal. Memory is normal. But users are seeing failures. The server filesystem is almost full.

We investigate from **symptom** to **root cause** to **fix** to **prevention**, following the same path an SRE would take during a real on-call incident.

**The primary incident:** Uncontrolled application log growth fills a filesystem, causing application failures.

**The secondary surprise:** After deleting the huge log file, disk space is NOT reclaimed — because a process still has the file open. We discover this with `lsof +L1`.

**The brief side-path:** Inode exhaustion — "disk full" does not always mean bytes are full.

We do NOT reveal the root cause upfront. We discover it through investigation, just like a real incident.

---

## 2. Learning Objectives

By the end of this episode, you will understand:

1. What application logs are and why they grow.
2. Why uncontrolled log growth can fill a Linux filesystem.
3. What happens to applications when a filesystem runs out of space.
4. How to troubleshoot a disk-full incident (`df`, `du`, `find`, `lsof`).
5. What logrotate actually does.
6. How rotation, compression, retention, and deletion work.
7. How logrotate is scheduled and executed.
8. What `copytruncate` means and its tradeoffs.
9. Why simply deleting a log file can sometimes NOT release disk space.
10. What "deleted but still open" means at the Linux file-descriptor level.
11. How `df`, `du`, `find`, and `lsof` help during a real incident.
12. Briefly: inode exhaustion and how it differs from storage exhaustion.
13. How production applications like Nginx coordinate log rotation.
14. How to design a sensible log-retention policy.

---

## 3. Final Lab Architecture

```
                    Proxmox
                       |
                       v
                  Ubuntu VM
                       |
              +--------+--------+
              |                 |
          Demo App        Demo Filesystem
              |                 |
              v                 v
          app.log -----> /var/log/myapp
                              |
                           ~500 MB
                           (loopback)
                              |
                              v
                          DISK FULL
```

**Components:**

| Component | Purpose |
|-----------|---------|
| Ubuntu VM on Proxmox | Safe, isolated lab environment |
| 500 MB loopback ext4 filesystem | Isolated disk for the demo — never touches real root FS |
| `/var/log/myapp` | Mount point for the demo filesystem |
| `myapp-loggen.sh` | Demo application that generates realistic log lines |
| `app.log` | The log file that grows until the filesystem is full |
| `logrotate` | The tool we use to manage the log lifecycle |
| `/etc/logrotate.d/myapp` | Logrotate configuration for the demo app |

---

## 4. Prerequisites

### 4.1 Environment

- An Ubuntu VM (22.04 LTS or 24.04 LTS recommended) running on Proxmox.
- At least 1 GB of free RAM and 2 GB of free disk on the VM's real root filesystem.
- `sudo` access on the VM.

### 4.2 Required Packages

Most of these are pre-installed on Ubuntu. Verify and install if needed:

```bash
# What it does: Checks and installs required tools.
# Why we run it: Ensure logrotate, lsof, and other utilities are present.

sudo apt update
sudo apt install -y logrotate lsof util-linux coreutils
```

**Expected output:**
```
# If already installed:
logrotate is already the newest version (3.x.x-1ubuntu1).
lsof is already the newest version (4.x.x-1).
# If not installed, apt will download and install them.
```

**Conclusion:** All required tools are available.

### 4.3 Verify logrotate is installed

```bash
# What it does: Checks the logrotate version.
# Why we run it: Confirm logrotate is available before we start.

logrotate --version
```

**Expected output (example):**
```
logrotate 3.21.0
```

**Conclusion:** logrotate is installed and ready.

---

## 5. Safe Isolated Filesystem Setup

> **CRITICAL SAFETY NOTE:** We will create a 500 MB loopback filesystem mounted at `/var/log/myapp`. This is completely isolated from the VM's real root filesystem. All disk-full incidents happen on this 500 MB filesystem only. The real root filesystem is never at risk.

### 5.1 Create the mount point

```bash
# What it does: Creates the directory /var/log/myapp.
# Why we run it: This is where our demo filesystem will be mounted and where
#                the demo application will write its logs.

sudo mkdir -p /var/log/myapp
```

**Expected output:** None (silent on success).

**Conclusion:** The mount point directory exists.

### 5.2 Create a 500 MB loopback image file

```bash
# What it does: Creates a 500 MB file filled with zeros at /tmp/myapp-fs.img.
# Why we run it: This file will be used as the backing store for our isolated
#                loopback filesystem. We put it in /tmp so it lives on the real
#                root filesystem but is clearly a temporary demo artifact.
#                500 MB is small enough to be safe but large enough for a
#                realistic demo.

sudo dd if=/dev/zero of=/tmp/myapp-fs.img bs=1M count=500 status=progress
```

**Expected output (example):**
```
500+0 records in
500+0 records out
524288000 bytes (524 MB, 500 MiB) copied, 1.2 s, 437 MB/s
```

**Conclusion:** A 500 MB image file has been created.

### 5.3 Format the image as ext4

```bash
# What it does: Formats the image file with the ext4 filesystem.
# Why we run it: ext4 is the default Linux filesystem. We format our isolated
#                image so it has its own independent storage capacity, inode
#                table, and free-space tracking — completely separate from the
#                root filesystem.

sudo mkfs.ext4 /tmp/myapp-fs.img
```

**Expected output (example):**
```
mke2fs 1.46.5 (30-Dec-2021)
Discarding device blocks: done
Creating filesystem with 512000 1k blocks and 128016 inodes
Filesystem UUID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Superblock backups stored on blocks:
        8193, 24577, 40961, 57345, 73729, 204801, 221185, 401409

Allocating group tables: done
Writing inode tables: done
Creating journal: 8192 blocks, done
Writing superblocks and filesystem accounting information: done
```

**Conclusion:** The image is now a valid ext4 filesystem with ~500 MB capacity and ~128K inodes.

### 5.4 Mount the filesystem

```bash
# What it does: Mounts the image file as a loopback device at /var/log/myapp.
# Why we run it: This makes the isolated filesystem accessible at /var/log/myapp.
#                The 'loop' option tells Linux to treat the image file as a
#                block device.

sudo mount -o loop /tmp/myapp-fs.img /var/log/myapp
```

**Expected output:** None (silent on success).

**Conclusion:** The isolated filesystem is now mounted and ready.

### 5.5 Verify the mount

```bash
# What it does: Shows all mounted filesystems, filtered for our demo mount.
# Why we run it: Confirm the loopback filesystem is mounted at the right place
#                with the right size.

mount | grep myapp
```

**Expected output (example):**
```
/tmp/myapp-fs.img on /var/log/myapp type ext4 (rw,loop)
```

```bash
# What it does: Shows filesystem usage for our demo mount.
# Why we run it: Confirm the capacity is ~500 MB and mostly free.

df -h /var/log/myapp
```

**Expected output (example):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  2.1M  450M   1% /var/log/myapp
```

> **Note:** The exact loop device number (`loop0`, `loop1`, etc.) and exact sizes may vary depending on your VM. The key point is: ~500 MB total, mostly free, mounted at `/var/log/myapp`.

**Conclusion:** The isolated 500 MB filesystem is mounted and ready for the demo.

### 5.6 Set permissions

```bash
# What it does: Sets ownership so the demo app can write to the directory.
# Why we run it: The log generator script needs write access to /var/log/myapp.

sudo chown $USER:$USER /var/log/myapp
sudo chmod 755 /var/log/myapp
```

**Expected output:** None (silent on success).

**Conclusion:** The demo directory is writable.

---

## 6. Demo Application / Log Generator

### 6.1 What is an application log?

Before we create the demo app, let's understand what a log is.

**A log is simply information recorded by an application.** It may be written to a file, sent to a network service, or printed to the console. In our case, the application writes to a file.

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

**Analogy:**
> The log is like a notebook. Every request adds another page. If nobody removes old pages, the notebook eventually becomes huge.

Every log line consumes storage. If the application keeps appending to the same file, that file keeps growing — forever — until something stops it.

### 6.2 Create the log generator script

```bash
# What it does: Creates a script that generates realistic log lines continuously.
# Why we run it: We need a demo "application" that produces log output so we can
#                observe log growth in a controlled way.

sudo tee /usr/local/bin/myapp-loggen.sh > /dev/null << 'SCRIPT'
#!/bin/bash
#
# myapp-loggen.sh — Demo application log generator
# Generates realistic log lines for the "When Logs Kill Servers" episode.
#

LOGFILE="/var/log/myapp/app.log"

# Ensure the log directory exists
mkdir -p /var/log/myapp

# Counter for request IDs
REQ_ID=1000

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Mostly INFO, occasionally ERROR
    if [ $((RANDOM % 10)) -eq 0 ]; then
        echo "$TIMESTAMP ERROR request_id=$REQ_ID database timeout" >> "$LOGFILE"
    else
        echo "$TIMESTAMP INFO request_id=$REQ_ID request processed" >> "$LOGFILE"
    fi

    REQ_ID=$((REQ_ID + 1))

    # Small delay — adjust to control growth rate
    sleep 0.01
done
SCRIPT

sudo chmod +x /usr/local/bin/myapp-loggen.sh
```

**Expected output:** None (file created silently).

**Conclusion:** The log generator script is installed and executable.

### 6.3 Test the log generator (briefly)

```bash
# What it does: Runs the log generator for ~3 seconds to verify it works.
# Why we run it: Confirm the script produces realistic log lines before we
#                start the full incident simulation.

timeout 3 /usr/local/bin/myapp-loggen.sh
```

```bash
# What it does: Shows the first few log lines.
# Why we run it: Verify the log format looks realistic.

head -5 /var/log/myapp/app.log
```

**Expected output (example):**
```
2026-09-15 10:31:01 INFO request_id=1000 request processed
2026-09-15 10:31:01 INFO request_id=1001 request processed
2026-09-15 10:31:01 ERROR request_id=1002 database timeout
2026-09-15 10:31:01 INFO request_id=1003 request processed
2026-09-15 10:31:01 INFO request_id=1004 request processed
```

**Conclusion:** The log generator works and produces realistic log lines.

### 6.4 Clean up the test log

```bash
# What it does: Removes the test log file so we start fresh.
# Why we run it: We want a clean state before starting the real incident demo.

rm -f /var/log/myapp/app.log
```

**Expected output:** None (silent on success).

**Conclusion:** Clean slate for the incident demo.

---

## 7. Incident Injection

### 7.1 Start the log generator in the background

```bash
# What it does: Starts the log generator as a background process.
# Why we run it: This simulates our application running in production and
#                continuously writing logs. We use nohup so it survives
#                terminal close, and redirect its own output to /dev/null
#                so it doesn't clutter our terminal.

nohup /usr/local/bin/myapp-loggen.sh > /dev/null 2>&1 &
echo "Log generator PID: $!"
```

**Expected output (example):**
```
Log generator PID: 12345
```

**Conclusion:** The demo "application" is running and generating logs.

> **Note:** Save this PID — we'll need it later for the deleted-but-open demo and for cleanup.

### 7.2 Observe log growth

```bash
# What it does: Shows the size of the log file.
# Why we run it: Observe the log file growing over time.

ls -lh /var/log/myapp/app.log
```

**Expected output (example, will vary with time):**
```
-rw-r--r-- 1 ubuntu ubuntu 1.2M Sep 15 10:31 /var/log/myapp/app.log
```

```bash
# What it does: Shows the total size of the demo log directory.
# Why we run it: Track overall consumption on the demo filesystem.

du -sh /var/log/myapp
```

**Expected output (example):**
```
1.2M    /var/log/myapp
```

### 7.3 Accelerate the growth (optional, for demo pacing)

The default `sleep 0.01` produces moderate growth. For a faster demo, you can either:

**Option A:** Wait a few minutes with the default rate.

**Option B:** Kill the current generator and restart with a faster rate:

```bash
# What it does: Stops the current log generator.
# Why we run it: We want to restart with a faster rate for demo pacing.

kill %1 2>/dev/null; sleep 1
```

```bash
# What it does: Creates a faster version that opens the log file ONCE and keeps
#                the file descriptor open, then writes to it continuously.
# Why we run it: (1) Fill the 500 MB filesystem faster for demo pacing.
#                (2) Keep the file descriptor open so we can demonstrate the
#                    "stale FD" problem with lsof in Phase 14.

sudo tee /usr/local/bin/myapp-loggen-fast.sh > /dev/null << 'SCRIPT'
#!/bin/bash
#
# myapp-loggen-fast.sh — Fast log generator for demo pacing
# Opens the log file ONCE and keeps the FD open.
#

LOGFILE="/var/log/myapp/app.log"
mkdir -p /var/log/myapp
REQ_ID=1000

# Open the log ONCE and keep the file descriptor open.
exec >> "$LOGFILE" 2>&1

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    if [ $((RANDOM % 10)) -eq 0 ]; then
        echo "$TIMESTAMP ERROR request_id=$REQ_ID database timeout connection=pool-1 host=db.internal latency=5000ms"
    else
        echo "$TIMESTAMP INFO request_id=$REQ_ID request processed method=GET path=/api/v1/resource status=200 duration=15ms user=user@example.com"
    fi

    REQ_ID=$((REQ_ID + 1))
done
SCRIPT

sudo chmod +x /usr/local/bin/myapp-loggen-fast.sh
nohup /usr/local/bin/myapp-loggen-fast.sh > /dev/null 2>&1 &
echo "Fast log generator PID: $!"
```

**Expected output (example):**
```
Fast log generator PID: 12350
```

### 7.4 Watch the filesystem fill up

```bash
# What it does: Monitors the filesystem usage in real-time.
# Why we run it: Watch the demo filesystem fill up toward 100%.
#                Press Ctrl+C to stop watching once it's near full.

watch -n 2 'df -h /var/log/myapp && echo "---" && ls -lh /var/log/myapp/app.log'
```

**Expected output (example, will change over time):**
```
Every 2.0s: df -h /var/log/myapp && echo "---" && ls -lh /var/log/myapp/app.log

Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  350M  100M  78% /var/log/myapp
---
-rw-r--r-- 1 ubuntu ubuntu 345M Sep 15 10:35 /var/log/myapp/app.log
```

Wait until `Use%` reaches 95% or higher, then press `Ctrl+C`.

### 7.5 The incident: filesystem is nearly full

```bash
# What it does: Shows the current filesystem state.
# Why we run it: This is the "incident" — our filesystem is almost full.

df -h /var/log/myapp
```

**Expected output (example):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

**Conclusion:** The filesystem is 95% full. This is our incident.

### 7.6 Show the application failing

At this point, the log generator is still running. Let's show what happens when the filesystem actually hits 100%.

```bash
# What it does: Attempts to write a new file on the nearly-full filesystem.
# Why we run it: Demonstrate that a full filesystem causes writes to fail.
#                This simulates what happens to real applications that need
#                to write temporary files, state, PID files, etc.

echo "test write" > /var/log/myapp/test-write.txt
```

**Expected output (when filesystem is at 100%):**
```
bash: /var/log/myapp/test-write.txt: No space left on device
```

**Conclusion:** A storage problem has become an application outage. The application cannot write, and any operation that requires disk space will fail.

**Key point:**
> A storage problem can become an application outage. Even if the application code is perfectly healthy, it can fail because it cannot write temporary files, uploads, database writes, application state, PID files, caches, or additional logs.

---

## 8. Initial Disk Investigation

Now we investigate like an SRE. We do NOT jump to logrotate yet. First, we need to understand what resource is actually exhausted.

### 8.1 Check filesystem storage capacity

```bash
# What it does: Shows disk usage for all mounted filesystems.
# Why we run it: Determine which filesystem is full and how much space
#                is available. This is always the first command in a
#                disk-full investigation.

df -h
```

**Expected output (example — only relevant lines shown):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        20G   8.2G   11G  44% /
tmpfs           2.0G     0  2.0G   0% /dev/shm
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

**What we learn:** The root filesystem (`/dev/sda1`) is fine at 44%. Our demo filesystem (`/dev/loop0`) at `/var/log/myapp` is at 95%.

**Analogy:**
> `df` tells us "how full is the warehouse?" It tells us the total capacity and how much is used, but not what's inside.

### 8.2 Check specifically for our demo filesystem

```bash
# What it does: Shows disk usage for just our demo filesystem.
# Why we run it: Focus on the filesystem that triggered the alert.

df -h /var/log/myapp
```

**Expected output (example):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

**Conclusion:** The isolated demo filesystem is nearly full. The root filesystem is fine.

---

## 9. Brief Inode Exhaustion Side-Path

> **IMPORTANT:** This is a SHORT side-path. We introduce the concept, demonstrate `df -i`, and return to the main investigation. We do NOT create a full inode-exhaustion lab.

### 9.1 The two resources a filesystem tracks

Before we continue, there's one more way Linux can report "No space left on device" that you should know about.

Linux filesystems track **two** different resources:

```
Filesystem
    |
    +-- Storage blocks
    |      └── DATA capacity (how many bytes can be stored)
    |
    +-- Inodes
           └── FILE/OBJECT capacity (how many files can be created)
```

- **Storage blocks** = how much data you can store (bytes).
- **Inodes** = how many files/directories you can create (file metadata slots).

### 9.2 Check inode usage

```bash
# What it does: Shows inode usage for all mounted filesystems.
# Why we run it: Check whether we're out of inodes, not just out of bytes.
#                This is a quick check — if inodes are fine, we return to
#                the main investigation.

df -i
```

**Expected output (example — only relevant lines shown):**
```
Filesystem      Inodes IUsed IFree IUse% Mounted on
/dev/sda1      1.3M    180K  1.1M   14% /
/dev/loop0      128K     12   128K    1% /var/log/myapp
```

**What we learn:** Inodes on our demo filesystem are at 1% — not exhausted. The problem is storage blocks (bytes), not inodes.

### 9.3 The conceptual example

To understand when inode exhaustion WOULD be the problem, consider this scenario:

```
Disk (storage blocks):
    20 GB total
    2 GB used
    18 GB free        ← plenty of space!

BUT:

Inodes:
    100% used         ← no file slots left!

Result:
    "No space left on device"
    (even though df -h shows 18 GB free)
```

This happens when you have millions of tiny files — session files, cache shards, mail queue entries, etc.

**Analogy:**
> Imagine a warehouse with plenty of floor space, but you've run out of name tags. Every item needs a name tag to be stored. No name tags = no new items, even with empty floor space.

### 9.4 Summary of the side-path

```
df -h  →  storage blocks  →  "How many bytes are left?"
df -i  →  inodes           →  "How many file slots are left?"
```

Both can cause "No space left on device." Always check both.

**In our case:** `df -i` shows inodes are fine. The problem is bytes. We return to the main investigation.

---

## 10. Identifying the Large Log

### 10.1 Find which directory is consuming the space

```bash
# What it does: Shows the size of each top-level subdirectory under /var,
#                staying on the same filesystem (-x flag).
# Why we run it: Narrow down which part of the filesystem tree is consuming
#                the most space.

sudo du -xhd1 /var | sort -h
```

**Expected output (example):**
```
4.0K    /var/local
4.0K    /var/mail
8.0K    /var/opt
...
150M    /var/log
475M    /var/log/myapp
```

> **Note:** If `/var/log/myapp` is a separate mount, `du -x` on `/var` won't descend into it (because `-x` stays on one filesystem). In that case, run `du` directly on the mount point:

```bash
# What it does: Shows the size of the demo filesystem contents.
# Why we run it: Since /var/log/myapp is a separate mount, we check it directly.

sudo du -sh /var/log/myapp
```

**Expected output (example):**
```
475M    /var/log/myapp
```

**Conclusion:** `/var/log/myapp` is consuming almost all the space on our demo filesystem.

### 10.2 Drill into the directory

```bash
# What it does: Shows the size of each item inside /var/log/myapp.
# Why we run it: Identify which specific file(s) are consuming the space.

sudo du -ah /var/log/myapp | sort -h
```

**Expected output (example):**
```
4.0K    /var/log/myapp
475M    /var/log/myapp/app.log
```

**Conclusion:** A single file — `app.log` — is consuming almost all 475 MB.

### 10.3 Find large files directly

```bash
# What it does: Finds files larger than 100 MB on the demo filesystem.
# Why we run it: Cross-reference our du finding with a direct file search.
#                This is the command you'd use in a real investigation when
#                you don't know which directory to start in.

sudo find /var/log/myapp -type f -size +100M -ls
```

**Expected output (example):**
```
   12  61440 -rw-r--r--   1 ubuntu ubuntu 475235072 Sep 15 10:35 /var/log/myapp/app.log
```

**Conclusion:** Confirmed — `app.log` is the single huge file consuming the filesystem.

### 10.4 The three investigation tools — what each answers

```
df  → "How full is the filesystem?"        (warehouse capacity)
du  → "Which directories use the space?"    (which section of the warehouse)
find → "Which specific files are huge?"    (which individual boxes are huge)
```

**Analogy:**
> - `df` = "How full is the warehouse?"
> - `du` = "Which section of the warehouse is using the space?"
> - `find` = "Which individual boxes are huge?"

### 10.5 Root cause identified

Now we can connect the dots:

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

**Only now** do we introduce logrotate as the solution.

---

## 11. Logrotate Explanation

### 11.1 What logrotate is — and what it is NOT

**Logrotate is NOT the application logging system.** It does not create logs. The application creates logs.

**Logrotate manages the lifecycle of logs that already exist.**

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

### 11.2 The lifecycle logrotate provides

Without logrotate:
```
app.log → grows → grows → grows → DISK FULL
```

With logrotate:
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
eventually deleted (app.log.8.gz is removed when app.log.9 is created)
```

### 11.3 The four concepts

| Concept | What it does | Why it matters |
|---------|-------------|----------------|
| **Rotation** | Rename the current log and start a fresh one | Prevents any single file from growing forever |
| **Compression** | Gzip the rotated log | Reduces disk usage by 10–20x |
| **Retention** | Keep only N generations | Caps total disk usage |
| **Deletion** | Remove generations beyond the retention limit | Ensures old logs don't accumulate |

---

## 12. Logrotate Configuration

### 12.1 Create the logrotate config

```bash
# What it does: Creates a logrotate configuration file for our demo app.
# Why we run it: This is the fix for our incident — a proper log lifecycle
#                policy for the demo application's log.

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

**Expected output:** None (file created silently).

### 12.2 Explain every directive

Let's break down each directive:

#### `daily`
- **What it does:** Rotate the log once per day.
- **Why it matters:** Controls how often rotation happens. You can also use `weekly`, `monthly`, or `size 100M` to rotate based on file size instead of time.

#### `rotate 7`
- **What it does:** Keep 7 rotated copies before deleting the oldest.
- **Why it matters:** This is your **retention policy**. With `rotate 7` and `daily`, you keep a week of logs. Older generations are automatically deleted.

#### `compress`
- **What it does:** Compress rotated logs with gzip.
- **Why it matters:** A 100 MB log file typically compresses to 5–10 MB. This dramatically reduces disk usage.

#### `missingok`
- **What it does:** Don't error if the log file doesn't exist.
- **Why it matters:** If the application hasn't created the log yet (or was restarted), logrotate should skip gracefully, not fail.

#### `notifempty`
- **What it does:** Don't rotate if the log file is empty.
- **Why it matters:** Avoid creating useless empty rotated files.

#### `copytruncate`
- **What it does:** Instead of moving the log file and creating a new one, copy the current log to the rotated name, then truncate the original to zero size.
- **Why it matters:** The application keeps writing to the same file descriptor. No need to signal the application to reopen its log. We'll dive deeper into this in Phase 17.

### 12.3 Visual: the rotation lifecycle

```
app.log (current, being written to)
   |
   | logrotate runs (daily)
   v
app.log.1 (yesterday's log, uncompressed briefly)
   |
   | compression
   v
app.log.1.gz (compressed, uses much less space)
   |
   | next day: app.log.2.gz created, app.log.1.gz becomes app.log.2.gz
   |
   v
... after 7 days ...
   |
   v
app.log.7.gz (oldest retained copy)
   |
   | next rotation
   v
app.log.7.gz is DELETED
app.log.8.gz does not exist
```

---

## 13. Rotation / Compression / Retention Demo

### 13.1 Dry run — debug mode

```bash
# What it does: Runs logrotate in debug mode. Shows what WOULD happen
#                without actually doing anything.
# Why we run it: Always dry-run a new logrotate config before applying it
#                for real. This is a best practice — verify before executing.

sudo logrotate -d /etc/logrotate.d/myapp
```

**Expected output (example — key lines):**
```
warning: logrotate version is 3.21.0, but the config file uses an older format
reading config file /etc/logrotate.d/myapp
Allocating hash table for state file, size 15360 B

Handling 1 log

rotating pattern: /var/log/myapp/app.log  daily (7 rotations)
empty log files are not rotated, old logs are removed
considering log /var/log/myapp/app.log
  log /var/log/myapp/app.log does not need rotating
```

> **Note:** "does not need rotating" means the log hasn't reached its rotation threshold yet (it's not yet a day old since the last rotation, or there's no state file yet). This is expected in debug mode.

**Conclusion:** The config is valid. logrotate understands our directives.

### 13.2 Force a rotation

```bash
# What it does: Forces logrotate to rotate the log immediately, regardless
#                of the normal schedule.
# Why we run it: For demo purposes, we don't want to wait 24 hours. The -f
#                flag forces rotation now so we can see the result.

sudo logrotate -f /etc/logrotate.d/myapp
```

**Expected output:** None (silent on success).

### 13.3 Observe the result

```bash
# What it does: Lists the files in the demo log directory.
# Why we run it: See what logrotate produced after the forced rotation.

ls -lh /var/log/myapp/
```

**Expected output (example):**
```
total 478M
-rw-r--r-- 1 ubuntu ubuntu 1.2M Sep 15 10:36 app.log
-rw-r--r-- 1 ubuntu ubuntu 475M Sep 15 10:35 app.log.1
```

**What happened:**
- `app.log` is now small (the log generator started writing fresh after truncation).
- `app.log.1` is the old content (uncompressed for now — compression happens on the next rotation cycle by default, unless `delaycompress` is absent, in which case it compresses immediately).

> **Note:** With `compress` (and no `delaycompress`), logrotate compresses `app.log.1` immediately. You may see `app.log.1.gz` instead of `app.log.1`. The exact behavior depends on your logrotate version. Let's check:

```bash
# What it does: Lists files with gzip detection.
# Why we run it: Confirm whether compression happened immediately.

ls -lh /var/log/myapp/
```

If you see `app.log.1.gz`:
```
-rw-r--r-- 1 ubuntu ubuntu 1.2M Sep 15 10:36 app.log
-rw-r--r-- 1 ubuntu ubuntu  35M Sep 15 10:35 app.log.1.gz
```

**Conclusion:** Rotation worked. The old log was rotated and compressed. The new `app.log` is small.

### 13.4 Generate more logs and rotate again

```bash
# What it does: The log generator is still running, so app.log is growing.
#                We wait a moment, then force another rotation.
# Why we run it: Demonstrate multiple rotation generations.

sleep 5
sudo logrotate -f /etc/logrotate.d/myapp
ls -lh /var/log/myapp/
```

**Expected output (example):**
```
-rw-r--r-- 1 ubuntu ubuntu 2.1M Sep 15 10:37 app.log
-rw-r--r-- 1 ubuntu ubuntu  35M Sep 15 10:36 app.log.1.gz
-rw-r--r-- 1 ubuntu ubuntu  30M Sep 15 10:37 app.log.2.gz
```

### 13.5 Repeat to show retention in action

```bash
# What it does: Forces several more rotations to demonstrate retention.
# Why we run it: Show that only 7 generations are kept — older ones are
#                automatically deleted.

for i in $(seq 1 8); do
    sleep 2
    sudo logrotate -f /etc/logrotate.d/myapp
done
ls -lh /var/log/myapp/
```

**Expected output (example):**
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

**Conclusion:** Exactly 7 rotated copies are retained (plus the current `app.log`). Older generations were automatically deleted. Disk usage is now bounded.

### 13.6 Verify disk usage is under control

```bash
# What it does: Shows filesystem usage after logrotate is working.
# Why we run it: Confirm that logrotate has brought disk usage under control.

df -h /var/log/myapp
```

**Expected output (example):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  220M  230M  49% /var/log/myapp
```

**Conclusion:** Disk usage dropped from 95% to ~49%. The log lifecycle is now bounded.

---

## 14. Broken Retention Configuration Demo

### 14.1 The bad config

Now let's see what happens with a BAD configuration — rotation without sensible retention and without compression.

```bash
# What it does: Replaces the logrotate config with a bad one — too many
#                rotations and no compression.
# Why we run it: Demonstrate that rotation alone does NOT solve disk usage.
#                You need retention limits AND compression.

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

**What's wrong:**
- `rotate 100` — keeps 100 generations. Way too many for a 500 MB filesystem.
- No `compress` — rotated logs stay at full size.

### 14.2 Clean up and restart

```bash
# What it does: Cleans up the demo directory and restarts the log generator.
# Why we run it: Start fresh for the bad-config demo.

# Stop the log generator
pkill -f myapp-loggen 2>/dev/null
sleep 1

# Clean up old rotated files
rm -f /var/log/myapp/app.log*

# Restart the log generator
nohup /usr/local/bin/myapp-loggen-fast.sh > /dev/null 2>&1 &
echo "Log generator PID: $!"

# Wait for the log to grow
sleep 10
```

### 14.3 Rotate repeatedly with the bad config

```bash
# What it does: Forces several rotations with the bad config.
# Why we run it: Show that rotated files pile up without compression and
#                with excessive retention.

for i in $(seq 1 5); do
    sleep 3
    sudo logrotate -f /etc/logrotate.d/myapp
done
ls -lh /var/log/myapp/
```

**Expected output (example):**
```
-rw-r--r-- 1 ubuntu ubuntu 2.0M Sep 15 10:42 app.log
-rw-r--r-- 1 ubuntu ubuntu  90M Sep 15 10:42 app.log.1
-rw-r--r-- 1 ubuntu ubuntu  85M Sep 15 10:42 app.log.2
-rw-r--r-- 1 ubuntu ubuntu  88M Sep 15 10:42 app.log.3
-rw-r--r-- 1 ubuntu ubuntu  82M Sep 15 10:42 app.log.4
-rw-r--r-- 1 ubuntu ubuntu  80M Sep 15 10:42 app.log.5
```

```bash
df -h /var/log/myapp
```

**Expected output (example):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  475M   25M  95% /var/log/myapp
```

**Conclusion:** The filesystem is full AGAIN. Rotation without compression and with excessive retention simply moved the problem around. The logs are still consuming the same total space — they're just split across multiple files.

### 14.4 The lesson

> **Rotation alone does not solve disk usage.** You need:
> 1. **Compression** — to shrink rotated logs.
> 2. **Sensible retention** — to cap the number of generations.
> 3. **Both together** — to bound total disk consumption.

### 14.5 Restore the good config

```bash
# What it does: Restores the correct logrotate configuration.
# Why we run it: Return to a working configuration with compression and
#                sensible retention.

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

### 14.6 How to design a sensible retention policy

Retention should depend on:

| Factor | Consideration |
|--------|--------------|
| **Log volume** | High-volume logs need fewer generations or more frequent rotation |
| **Disk capacity** | How much space can you dedicate to logs? |
| **Operational requirements** | How far back do you need to look for debugging? |
| **Compliance requirements** | Some regulations require 30/90/365 days of logs |
| **Historical visibility** | How long are logs useful for trend analysis? |

**Rule of thumb:**
```
Total log disk usage ≈ (log volume per rotation period) × (retention count) × (compression ratio)

Example:
  100 MB/day × 7 days × 0.1 (10x compression) = 70 MB total
  100 MB/day × 30 days × 0.1 = 300 MB total
  100 MB/day × 90 days × 0.1 = 900 MB total
```

---

## 15. Logrotate Scheduler Explanation

### 15.1 Logrotate does NOT run continuously

A common misconception: logrotate watches your log files in real time. **It does not.**

Logrotate is a **batch tool**. It runs periodically, does its work, and exits. Something else schedules it.

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

### 15.2 Check the scheduler on Ubuntu

On modern Ubuntu, logrotate is scheduled by a systemd timer:

```bash
# What it does: Shows the status of the logrotate systemd timer.
# Why we run it: Confirm how and when logrotate is scheduled to run.

systemctl status logrotate.timer
```

**Expected output (example):**
```
● logrotate.timer - Daily rotation of log files
     Loaded: loaded (/lib/systemd/system/logrotate.timer; enabled)
     Active: active (waiting) since Tue 2026-09-15 10:00:00 UTC; 30min ago
    Trigger: Wed 2026-09-16 00:00:00 UTC; 13h left
   Triggers: ● logrotate.service

Sep 15 10:00:00 ubuntu systemd[1]: Started Daily rotation of log files.
```

```bash
# What it does: Lists all systemd timers, filtered for logrotate.
# Why we run it: See when logrotate is next scheduled to run.

systemctl list-timers | grep logrotate
```

**Expected output (example):**
```
NEXT                        LEFT       LAST                        PASSED  UNIT            ACTIVATES
Wed 2026-09-16 00:00:00 UTC 13h left   Tue 2026-09-15 10:00:00 UTC 30min ago logrotate.timer logrotate.service
```

**Conclusion:** logrotate runs daily at midnight (by default) via a systemd timer.

### 15.3 Inspect the main config

```bash
# What it does: Shows the main logrotate configuration file.
# Why we run it: Understand the global settings that apply to all logrotate
#                configs, including the default schedule and include directive.

cat /etc/logrotate.conf
```

**Expected output (example — key lines):**
```
weekly
rotate 4

# use the syslog-ng logrotate policy
include /etc/logrotate.d
```

> **Note:** The main config sets defaults (`weekly`, `rotate 4`). Individual configs in `/etc/logrotate.d/` can override these. Our `myapp` config overrides with `daily` and `rotate 7`.

### 15.4 Inspect the config directory

```bash
# What it does: Lists all individual logrotate configurations.
# Why we run it: See what other apps have logrotate configs on this system.

ls /etc/logrotate.d/
```

**Expected output (example):**
```
alternatives  apt  chrony  dpkg  myapp  rsyslog  ufw
```

**Conclusion:** Our `myapp` config sits alongside system configs. logrotate processes all of them on each run.

> **Note:** Exact scheduling can vary by Ubuntu version and configuration. On older systems, logrotate may be run via `/etc/cron.daily/logrotate` instead of a systemd timer. Check your specific system.

---

## 16. Deleted-but-Open File Demo

> This is the major surprise of the episode. We delete a log file, but disk space is NOT reclaimed — because a process still has the file open.

### 16.1 Set up the scenario

First, let's make sure we have a process holding the log file open. Our log generator is still running and writing to `app.log`.

```bash
# What it does: Confirms the log generator is running and writing to app.log.
# Why we run it: We need a process with an open file descriptor to app.log
#                for this demo.

# Find the log generator's PID
pgrep -f myapp-loggen
```

**Expected output (example):**
```
12350
```

```bash
# What it does: Shows the current filesystem state.
# Why we run it: Record the "before" state before we delete the file.

df -h /var/log/myapp
ls -lh /var/log/myapp/
```

**Expected output (example):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  300M  160M  63% /var/log/myapp

total 301M
-rw-r--r-- 1 ubuntu ubuntu 280M Sep 15 10:45 app.log
-rw-r--r-- 1 ubuntu ubuntu  20M  Sep 15 10:44 app.log.1.gz
```

### 16.2 Delete the log file

```bash
# What it does: Deletes the app.log file.
# Why we run it: This is what many people do when they find a huge log file —
#                they just rm it. We're about to show why this might not
#                free the disk space you expect.

sudo rm /var/log/myapp/app.log
```

**Expected output:** None (silent on success).

### 16.3 Check: the file is gone

```bash
# What it does: Lists the directory contents.
# Why we run it: Confirm the file is no longer visible.

ls -lh /var/log/myapp/
```

**Expected output (example):**
```
total 20M
-rw-r--r-- 1 ubuntu ubuntu 20M Sep 15 10:44 app.log.1.gz
```

**Conclusion:** `app.log` is gone from the directory listing.

### 16.4 Check: did disk space free up?

```bash
# What it does: Shows the current filesystem usage.
# Why we run it: Check whether deleting the file actually freed disk space.
#                This is the surprise — it often does NOT.

df -h /var/log/myapp
```

**Expected output (example — the surprise):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M  300M  160M  63% /var/log/myapp
```

**The file is gone, but disk usage is UNCHANGED.** The 280 MB is still consumed.

### 16.5 Why does this happen?

On Linux, deleting a file only removes its **directory entry** (the name). If a process still has the file **open** (via a file descriptor), the kernel keeps the inode and its data blocks alive until the last file descriptor is closed.

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

**Analogy:**
> The filename is like the label on a storage box. Removing the label does not necessarily mean the person currently using the box has stopped using it. The box (and its contents) stays in the warehouse until the person is done with it.

### 16.6 Find the deleted-but-open file with lsof

```bash
# What it does: Lists open files with link count < 1 — i.e., files that
#                have been deleted from the filesystem but still have
#                open file descriptors.
# Why we run it: This is THE command for finding deleted-but-open files.
#                The +L1 flag is the key — it filters for files where the
#                link count is less than 1 (meaning the filename has been
#                removed but the file is still held open by a process).

sudo lsof +L1
```

**Expected output (example — key columns):**
```
COMMAND      PID    USER   FD   TYPE  SIZE/OFF NLINK  NODE NAME
myapp-logge 12350 ubuntu   3w   REG   280M    0   12345 /var/log/myapp/app.log (deleted)
```

**What we see:**
- `COMMAND`: the process holding the file open (our log generator)
- `PID`: the process ID (12350)
- `FD`: the file descriptor (3w = descriptor 3, opened for writing)
- `SIZE/OFF`: the size of the deleted file (280 MB!)
- `NLINK`: 0 (link count is 0 — the file has been unlinked/deleted)
- `NAME`: `/var/log/myapp/app.log (deleted)` — confirms it's our deleted log

**Alternative command:**

```bash
# What it does: Searches all open files for ones marked as "(deleted)".
# Why we run it: An alternative to +L1 that works on some systems where
#                +L1 has issues with certain filesystems.

sudo lsof | grep deleted
```

**Expected output (example):**
```
myapp-logge 12350 ubuntu   3w   REG   252,0  280M    12345 /var/log/myapp/app.log (deleted)
```

### 16.7 How the space is eventually released

The space is released when the process **closes the file descriptor**. This can happen when:

- The process exits (crashes, is killed, or stops normally).
- The process explicitly closes the file.
- The process reopens the log file (common with signal-based log reopening).
- The process is restarted.

### 16.8 Reclaim space WITHOUT restarting (the /proc trick)

You can truncate the deleted-but-open file via its file descriptor in `/proc`, which frees the disk blocks immediately while keeping the process running:

```bash
# What it does: Finds the file descriptor number for the deleted log file,
#                then truncates it to zero bytes via /proc.
# Why we run it: This reclaims the disk space WITHOUT restarting the process.
#                The process keeps running and keeps its file descriptor open,
#                but the file is now 0 bytes.

# Find the PID of the log generator
LOGGEN_PID=$(pgrep -f myapp-loggen)
echo "Log generator PID: $LOGGEN_PID"

# Find the file descriptor for the deleted app.log
# Look in /proc/<PID>/fd/ for the deleted file
ls -la /proc/$LOGGEN_PID/fd/ | grep deleted
```

**Expected output (example):**
```
l-wx------ 1 ubuntu ubuntu 64 Sep 15 10:46 3 -> /var/log/myapp/app.log (deleted)
```

The file descriptor is `3`. Now truncate it:

```bash
# What it does: Truncates the file backing descriptor 3 to zero bytes.
# Why we run it: This immediately frees the 280 MB of disk space while
#                the process continues running with the same open descriptor.
#                The process will continue writing to this descriptor, but
#                now starting from byte 0.

sudo sh -c ': > /proc/'$LOGGEN_PID'/fd/3'
```

> **Note:** We use `sudo sh -c` because the redirection needs to run with root privileges to access `/proc/<PID>/fd/`.

### 16.9 Verify space was reclaimed

```bash
# What it does: Shows the filesystem usage after truncation.
# Why we run it: Confirm that disk space was reclaimed without restarting
#                the process.

df -h /var/log/myapp
```

**Expected output (example):**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      477M   21M  430M   5% /var/log/myapp
```

**Conclusion:** The 280 MB has been reclaimed. The process is still running. No restart was needed.

### 16.10 The better approach: don't delete in the first place

The real lesson is: **don't just `rm` a log file that a process is writing to.** Instead:

1. Use `logrotate` with `copytruncate` (truncates in place, no deletion).
2. Or use `logrotate` with `postrotate` that signals the application to reopen its log file.
3. Or manually truncate: `: > /var/log/myapp/app.log` (if you just need to free space quickly).

```bash
# What it does: Truncates a file to zero bytes in place.
# Why we run it: This is the safe manual alternative to rm when a process
#                has the file open. The file descriptor stays valid, the
#                process keeps writing, but the file is now empty.

# (Don't run this now — we already truncated via /proc. This is for reference.)
# : > /var/log/myapp/app.log
```

---

## 17. copytruncate Deep Dive

### 17.1 Why copytruncate exists

When logrotate rotates a log file normally (without `copytruncate`), it:

1. **Moves** `app.log` → `app.log.1`
2. **Creates** a new empty `app.log`

The problem: the application still has its file descriptor pointing to what is now `app.log.1` (the moved file). The application keeps writing to the old file descriptor, which now points to the rotated file — NOT the new `app.log`.

```
Without copytruncate:

Application writes to fd → app.log (inode 100)
                             |
                             | logrotate MOVES the file
                             v
                          app.log.1 (inode 100)  ← app still writes here!
                          app.log (inode 200)    ← new empty file, app NOT writing here
```

The application would need to be signaled to close the old descriptor and open a new file (`app.log`). This is what `postrotate` scripts do (see Phase 18).

### 17.2 How copytruncate works

With `copytruncate`, logrotate:

1. **Copies** the contents of `app.log` to `app.log.1`
2. **Truncates** `app.log` to zero bytes (in place — same inode)

The application's file descriptor still points to the same inode. The file is now empty, and the application continues writing from the beginning.

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

### 17.3 The tradeoff

`copytruncate` is convenient — no need to signal the application. But it has a **small race window**:

> Between the copy and the truncate, any log lines written by the application may end up in the copy (app.log.1) AND be lost when the original is truncated.

In practice, this window is very small (milliseconds), and for most applications the potential loss of a few log lines during rotation is acceptable. But for high-throughput or audit-critical logging, this tradeoff may not be acceptable.

### 17.4 When to use copytruncate vs. postrotate

| Approach | Pros | Cons |
|----------|------|------|
| **copytruncate** | No need to signal the app; works with any app | Small race window; potential log line loss during rotation; copies the full file (uses extra disk briefly) |
| **postrotate + signal** | No race window; no extra copy; cleaner | Application must support log reopening (e.g., via SIGHUP, SIGUSR1) |

**Do NOT present copytruncate as universally best practice.** It's a pragmatic choice for applications that don't support log reopening. For applications that do (like Nginx, Apache, rsyslog), `postrotate` with a signal is cleaner.

---

## 18. Nginx Production Example

### 18.1 The preferred model: application-aware log reopening

For production applications that support it, the preferred log rotation model is:

```
app.log
   |
   | logrotate rotates: app.log → app.log.1, creates new app.log
   v
app.log.1 (old)    app.log (new, empty)
   |
   | postrotate: signal application to reopen logs
   v
Application closes old file descriptor
   |
   v
Application opens new app.log
   |
   v
Application writes to new app.log
```

### 18.2 Nginx logrotate configuration

Nginx is a common production example. On Ubuntu, the default Nginx logrotate config typically looks like this:

```bash
# What it does: Shows the default Nginx logrotate config if Nginx is installed.
# Why we run it: See how a real production application coordinates log rotation.

cat /etc/logrotate.d/nginx 2>/dev/null || echo "Nginx not installed — showing representative config:"
```

**Representative config (if Nginx is not installed):**

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

### 18.3 Explain the key directives

#### `postrotate ... endscript`
- **What it does:** Runs a script after rotation.
- **Why it matters:** This is where we signal the application to reopen its log files.

#### `kill -USR1 $(cat /var/run/nginx.pid)`
- **What it does:** Sends the USR1 signal to the Nginx master process.
- **Why it matters:** Nginx handles USR1 by **reopening its log files**. It closes the old file descriptor (pointing to the rotated file) and opens a new one pointing to the fresh `app.log`.

#### `delaycompress`
- **What it does:** Delays compression by one rotation cycle.
- **Why it matters:** The most recently rotated file (`app.log.1`) is not compressed immediately. This is important because the application may still have its file descriptor open to `app.log.1` for a brief moment during the postrotate signal. Compressing a file that's still being written to could cause issues.

#### `create 0640 www-data adm`
- **What it does:** Creates the new log file with specific permissions and ownership.
- **Why it matters:** Ensures the new `app.log` has the correct permissions for the application to write to it.

#### `sharedscripts`
- **What it does:** Runs the postrotate script once per config, not once per log file.
- **Why it matters:** If the config matches multiple log files (`*.log`), the signal is sent only once, not once per file.

### 18.4 The Nginx log-reopen flow

```
1. logrotate runs
2. app.log → app.log.1 (moved)
3. New empty app.log created with correct permissions
4. postrotate: kill -USR1 <nginx_pid>
5. Nginx receives USR1
6. Nginx closes old file descriptor (was pointing to app.log.1)
7. Nginx opens new file descriptor to app.log
8. Nginx continues writing to the new app.log
9. On next rotation: app.log.1 → app.log.1.gz (compressed, delaycompress)
```

**Key point:**
> `rotate` + `application log reopen` = cleaner production lifecycle. No race window, no extra copy, no potential log loss.

### 18.5 Other applications that support log reopening

| Application | Signal | Config |
|-------------|--------|--------|
| Nginx | USR1 | `kill -USR1 $(cat /var/run/nginx.pid)` |
| Apache | USR1 | `apachectl graceful` or `kill -USR1` |
| rsyslog | HUP | `kill -HUP $(cat /var/run/rsyslogd.pid)` |
| PostgreSQL | (logrotate not typically used) | Uses built-in log rotation |
| Node.js apps | (varies) | Depends on logging library |

### 18.6 Live Demo: Log Reopen Without Nginx

We don't need Nginx installed to see the reopen mechanism in action. We'll create a signal-aware version of our demo app that reopens its log file when it receives `SIGHUP` — the same mechanism, just with a different signal than Nginx's `USR1`.

#### 18.6.1 Create the signal-aware log generator

```bash
# What it does: Creates a log generator that reopens its log file on SIGHUP.
# Why we run it: We need a demo app that supports log reopening so we can
#                demonstrate the postrotate + signal pattern live, without
#                installing Nginx. The script traps SIGHUP and reopens the
#                log file — exactly what Nginx does with SIGUSR1.

sudo tee /usr/local/bin/myapp-loggen-reopen.sh > /dev/null << 'SCRIPT'
#!/bin/bash
#
# myapp-loggen-reopen.sh — Signal-aware demo log generator
# Reopens log file on SIGHUP (like Nginx does on SIGUSR1).
#

LOGFILE="/var/log/myapp/app.log"
REQ_ID=1000

# Function to (re)open the log file
open_log() {
    exec >> "$LOGFILE" 2>&1
}

# Function to handle SIGHUP — reopen the log file
reopen_log() {
    open_log
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO log reopened after SIGHUP" >> "$LOGFILE"
}

# Trap SIGHUP and call reopen_log
trap reopen_log HUP

# Open the log file initially
open_log

# Write logs continuously
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    if [ $((RANDOM % 10)) -eq 0 ]; then
        echo "$TIMESTAMP ERROR request_id=$REQ_ID database timeout" >> "$LOGFILE"
    else
        echo "$TIMESTAMP INFO request_id=$REQ_ID request processed" >> "$LOGFILE"
    fi
    REQ_ID=$((REQ_ID + 1))
done
SCRIPT

sudo chmod +x /usr/local/bin/myapp-loggen-reopen.sh
```

**Expected output:** None (file created silently).

**Conclusion:** The signal-aware log generator is installed. It will reopen its log file when it receives `SIGHUP`.

#### 18.6.2 Create a postrotate logrotate config (without copytruncate)

```bash
# What it does: Creates a logrotate config that uses postrotate + signal
#                instead of copytruncate.
# Why we run it: This is the "production-style" approach — rotate the file,
#                then signal the app to reopen. No copytruncate, no race
#                window. The postrotate script sends SIGHUP to our demo app.

sudo tee /etc/logrotate.d/myapp-reopen > /dev/null << 'CONFIG'
/var/log/myapp/app.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 ubuntu ubuntu
    postrotate
        kill -HUP $(cat /var/run/myapp-reopen.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
CONFIG
```

> **Note:** The `create` directive uses `ubuntu ubuntu` as the owner/group. Adjust to match your user if you're not running as the `ubuntu` user. The `postrotate` script reads the PID from `/var/run/myapp-reopen.pid` — we'll write the PID there when we start the app.

#### 18.6.3 Set up the demo

First, stop any existing log generator and clean up:

```bash
# What it does: Stops any running log generators and cleans up old logs.
# Why we run it: Start fresh for the reopen demo.

pkill -f myapp-loggen 2>/dev/null
sleep 2
rm -f /var/log/myapp/app.log*
```

Now start the signal-aware log generator and write its PID to the expected location:

```bash
# What it does: Starts the signal-aware log generator and saves its PID
#                to /var/run/myapp-reopen.pid (where the logrotate postrotate
#                script expects to find it).
# Why we run it: The postrotate script needs the PID to send SIGHUP.

nohup /usr/local/bin/myapp-loggen-reopen.sh > /dev/null 2>&1 &
REOPEN_PID=$!
echo $REOPEN_PID | sudo tee /var/run/myapp-reopen.pid > /dev/null
echo "Signal-aware log generator PID: $REOPEN_PID"
```

**Expected output (example):**
```
Signal-aware log generator PID: 12500
```

Wait a moment for logs to accumulate, then verify:

```bash
# What it does: Shows the current log file and its size.
# Why we run it: Confirm the app is writing logs before we rotate.

sleep 3
ls -lh /var/log/myapp/app.log
tail -3 /var/log/myapp/app.log
```

**Expected output (example):**
```
-rw-r--r-- 1 ubuntu ubuntu 1.5M Sep 15 10:50 /var/log/myapp/app.log
2026-09-15 10:50:02 INFO request_id=1002 request processed
2026-09-15 10:50:02 INFO request_id=1003 request processed
2026-09-15 10:50:02 INFO request_id=1004 request processed
```

#### 18.6.4 Demonstrate the reopen: force a rotation

```bash
# What it does: Forces logrotate to rotate the log using the postrotate config.
# Why we run it: This is the live demo. logrotate will:
#                1. Move app.log → app.log.1
#                2. Create a new empty app.log
#                3. Run the postrotate script, which sends SIGHUP to our app
#                4. The app catches SIGHUP and reopens app.log
#                5. New log lines now go to the NEW app.log

sudo logrotate -f /etc/logrotate.d/myapp-reopen
```

**Expected output:** None (silent on success).

#### 18.6.5 Verify the reopen worked

```bash
# What it does: Shows the files in the log directory and the last few lines
#                of the new app.log.
# Why we run it: Confirm that:
#                1. app.log.1 exists (the rotated old log)
#                2. app.log is small (the new log, freshly created)
#                3. The new app.log contains the "log reopened" line
#                4. New log lines are appearing in app.log, NOT app.log.1

ls -lh /var/log/myapp/
echo "--- New app.log (last 5 lines) ---"
tail -5 /var/log/myapp/app.log
echo "--- app.log.1 (last 5 lines) ---"
tail -5 /var/log/myapp/app.log.1
```

**Expected output (example):**
```
total 2.5M
-rw-r----- 1 ubuntu ubuntu  50K Sep 15 10:50 app.log
-rw-r--r-- 1 ubuntu ubuntu 1.5M Sep 15 10:50 app.log.1

--- New app.log (last 5 lines) ---
2026-09-15 10:50:03 INFO log reopened after SIGHUP
2026-09-15 10:50:03 INFO request_id=1005 request processed
2026-09-15 10:50:03 INFO request_id=1006 request processed
2026-09-15 10:50:03 INFO request_id=1007 request processed
2026-09-15 10:50:03 INFO request_id=1008 request processed

--- app.log.1 (last 5 lines) ---
2026-09-15 10:50:02 INFO request_id=1002 request processed
2026-09-15 10:50:02 INFO request_id=1003 request processed
2026-09-15 10:50:02 INFO request_id=1004 request processed
2026-09-15 10:50:02 INFO request_id=1005 request processed
2026-09-15 10:50:02 INFO request_id=1006 request processed
```

**What we see:**
- `app.log.1` contains the OLD log lines (before rotation).
- `app.log` contains the "log reopened after SIGHUP" marker line, followed by NEW log lines.
- The app successfully reopened the new log file after receiving SIGHUP.
- No log lines were lost — the old lines are in `app.log.1`, new lines are in `app.log`.

**Conclusion:** The postrotate + signal mechanism works. The app closed its old file descriptor and opened a new one pointing to the fresh `app.log`. This is exactly what Nginx does with `kill -USR1`.

#### 18.6.6 Contrast: what happens WITHOUT the signal (the problem)

To really appreciate the fix, let's see what happens when the app does NOT reopen the log. Let's temporarily use the fast log generator (which does NOT handle signals) with the postrotate config. We'll use `lsof` to prove what's happening at the file descriptor level.

```bash
# What it does: Stops the signal-aware app, starts the non-signal app,
#                and captures its PID.
# Why we run it: We need the PID to use lsof to inspect file descriptors.

# Stop the signal-aware app
pkill -f myapp-loggen-reopen 2>/dev/null
sleep 2
rm -f /var/log/myapp/app.log*

# Start the non-signal-aware app and capture its PID
nohup /usr/local/bin/myapp-loggen-fast.sh > /dev/null 2>&1 &
NON_SIGNAL_PID=$!
echo "Non-signal app PID: $NON_SIGNAL_PID"

sleep 3
```

**Expected output (example):**
```
Non-signal app PID: 12400
```

Now let's check the file descriptor BEFORE rotation:

```bash
# What it does: Shows which file the app's FD 1 (stdout) is pointing to.
# Why we run it: Prove that before rotation, the app writes to app.log.

echo "=== BEFORE rotation: app's FD 1 points to app.log ==="
sudo lsof -p "$NON_SIGNAL_PID" | grep app.log
```

**Expected output (example):**
```
=== BEFORE rotation: app's FD 1 points to app.log ===
myapp-loggen  12400 ubuntu  1w  REG  8,1  1234567 Sep 15 10:52 /var/log/myapp/app.log
```

**What we see:**
- FD `1w` (write) points to `/var/log/myapp/app.log`
- The app is writing to the correct file

Now force a rotation:

```bash
# What it does: Forces logrotate to rotate the log using the postrotate config.
# Why we run it: This is the critical moment. logrotate will:
#                1. Move app.log → app.log.1
#                2. Create a new empty app.log
#                3. Run postrotate, which sends SIGHUP to the app
#                4. The app IGNORES SIGHUP (it doesn't handle it)
#                5. The app's old FD is now pointing to app.log.1

sudo logrotate -f /etc/logrotate.d/myapp-reopen

sleep 1
```

Now check the file descriptor AFTER rotation:

```bash
# What it does: Shows which file the app's FD 1 is pointing to AFTER rotation.
# Why we run it: Prove that the app's FD is now stale — pointing to app.log.1
#                instead of the new app.log.

echo "=== AFTER rotation: app's FD 1 points to app.log.1 (STALE!) ==="
sudo lsof -p "$NON_SIGNAL_PID" | grep app.log
```

**Expected output (example):**
```
=== AFTER rotation: app's FD 1 points to app.log.1 (STALE!) ===
myapp-loggen  12400 ubuntu  1w  REG  8,1  1234567 Sep 15 10:52 /var/log/myapp/app.log.1
```

**This is the smoking gun:**
- FD `1w` now points to `/var/log/myapp/app.log.1` — NOT the new `app.log`
- The app's file descriptor is stale — it's pointing to the old inode
- The app is still alive and still writing, but to the wrong file

Verify by checking file sizes:

```bash
# What it does: Shows the current state of the log files.
# Why we run it: Confirm that app.log is empty (new, not being written to)
#                and app.log.1 is growing (old, still being written to).

echo "=== File sizes after rotation ==="
ls -lh /var/log/myapp/app.log*
echo "--- New app.log (empty) ---"
tail -3 /var/log/myapp/app.log
echo "--- app.log.1 (still growing!) ---"
tail -3 /var/log/myapp/app.log.1
```

**Expected output (example):**
```
=== File sizes after rotation ===
-rw-r----- 1 ubuntu ubuntu    0 Sep 15 10:52 /var/log/myapp/app.log
-rw-r--r-- 1 ubuntu ubuntu 5.2M Sep 15 10:52 /var/log/myapp/app.log.1

--- New app.log (empty) ---
(empty)

--- app.log.1 (still growing!) ---
2026-09-15 10:52:03 INFO request_id=2104 request processed method=GET path=/api/v1/resource status=200 duration=15ms user=user@example.com
2026-09-15 10:52:03 INFO request_id=2105 request processed method=GET path=/api/v1/resource status=200 duration=15ms user=user@example.com
2026-09-15 10:52:03 INFO request_id=2106 request processed method=GET path=/api/v1/resource status=200 duration=15ms user=user@example.com
```

**What we see:**
- `app.log` is EMPTY (0 bytes) — the app is NOT writing to it.
- `app.log.1` is GROWING — the app is still writing to the old file descriptor.
- The `postrotate` script sent `SIGHUP`, but the app doesn't handle it, so it ignored the signal.
- **The file descriptor is stale** — proven with `lsof`.

**Conclusion:** Without signal-aware log reopening, rotation breaks the log pipeline. The app's file descriptor becomes stale, pointing to the rotated file instead of the new one. This is why logrotate needs to communicate with the application — to tell it to close the old FD and open a new one. The `postrotate` + `SIGHUP` mechanism is how that communication happens.

#### 18.6.7 Clean up the reopen demo

```bash
# What it does: Stops the non-signal app, removes the reopen logrotate config
#                and PID file.
# Why we run it: Clean up the reopen demo before moving on.

pkill -f myapp-loggen 2>/dev/null
sleep 2
sudo rm -f /etc/logrotate.d/myapp-reopen
sudo rm -f /var/run/myapp-reopen.pid
rm -f /var/log/myapp/app.log*
```

---

## 19. Complete Troubleshooting Checklist

### 19.1 The SRE disk-full incident flow

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
   |                 |
   |                 +--> Is rotation configured?
   |                 +--> Is compression enabled?
   |                 +--> Is retention sensible?
   |                 +--> Is the scheduler running?
   |
   +---- NO ----> investigate other consumers
   |                 |
   |                 +--> core dumps?
   |                 +--> temp files?
   |                 +--> package cache?
   |                 +--> docker images?
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
verify df -h (confirm space reclaimed)
   |
   v
PREVENTION
```

### 19.2 Quick reference commands

```bash
# Step 1: Is the filesystem full?
df -h

# Step 2: Are inodes exhausted?
df -i

# Step 3: Which directories use the most space?
sudo du -xhd1 / | sort -h

# Step 4: Which specific files are huge?
sudo find / -xdev -type f -size +100M -ls

# Step 5: Are there deleted-but-open files?
sudo lsof +L1

# Step 6: Check logrotate config
cat /etc/logrotate.d/<appname>

# Step 7: Dry-run logrotate
sudo logrotate -d /etc/logrotate.d/<appname>

# Step 8: Force rotation
sudo logrotate -f /etc/logrotate.d/<appname>

# Step 9: Verify space reclaimed
df -h
```

---

## 20. Prevention / Best Practices

### 20.1 Production prevention strategies

1. **Sensible logrotate policies** — Every application that writes logs should have a logrotate config. Review and test it.

2. **Compression** — Always enable `compress` (and consider `delaycompress` for apps that reopen logs). A 100 MB log typically compresses to 5–10 MB.

3. **Retention limits** — Set `rotate` based on your disk capacity and operational needs. Don't keep 100 generations on a small filesystem.

4. **Application-aware log reopening** — For apps that support it (Nginx, Apache, rsyslog), use `postrotate` with a signal instead of `copytruncate`. Cleaner, no race window.

5. **Disk monitoring** — Monitor disk usage with tools like Prometheus node_exporter, Nagios, or simple scripts. Don't wait for 100%.

6. **Alerts before 100%** — Set alerts at 80% and 90%. Investigate at 80%, act at 90%. Never let a filesystem hit 100% in production.

7. **Centralized logging** — For large fleets, consider forwarding logs to a centralized system (ELK, Loki, Grafana, CloudWatch) instead of storing everything locally. This reduces local disk pressure and enables cross-host search.

8. **Container-specific log management** — Docker and container runtimes have their own logging mechanisms (json-file, journald, fluentd). Container logs should not automatically be treated exactly like traditional host log files. Use `docker logs` and configure log driver rotation (e.g., `--log-opt max-size=10m --log-opt max-file=3`).

9. **Configuration management** — Use Ansible, Puppet, or Chef to deploy logrotate configs consistently across your fleet. Don't manually edit `/etc/logrotate.d/` on individual servers.

10. **Review log volume after application changes** — After deploying a new version, check if log volume has changed. A new debug log line can 10x your log output.

### 20.2 The golden rule

> The goal is not simply "delete logs." The goal is to establish a **predictable log lifecycle**: logs are created, rotated, compressed, retained for a defined period, and then automatically deleted. No manual intervention needed.

---

## 21. Cleanup / Reset

> **WARNING: The following commands are DESTRUCTIVE.** They remove the demo filesystem, log generator, logrotate config, and all demo files. Run these ONLY when you are done with the episode and want to restore the VM to its original state.

### 21.1 Stop the log generator

```bash
# What it does: Kills the demo log generator process.
# Why we run it: Stop generating logs before we clean up.

pkill -f myapp-loggen 2>/dev/null
sleep 2
```

**Expected output:** None (or a confirmation of the killed process).

### 21.2 Stop any process holding the log file open

```bash
# What it does: Finds and kills any process with an open file descriptor
#                to the demo log directory.
# Why we run it: Ensure no process is holding the demo filesystem open
#                before we unmount it.

sudo lsof +L1 2>/dev/null | grep myapp
# If any process is listed, kill it:
# sudo kill <PID>
```

### 21.3 Remove the logrotate configuration

```bash
# What it does: Removes the demo logrotate config.
# Why we run it: Clean up the configuration we created for the demo.

sudo rm -f /etc/logrotate.d/myapp
```

### 21.4 Unmount the demo filesystem

```bash
# What it does: Unmounts the loopback filesystem from /var/log/myapp.
# Why we run it: Release the mount before removing the backing image.

sudo umount /var/log/myapp
```

**Expected output:** None (silent on success).

> If you get "target is busy", a process is still using the mount. Find and kill it:
> ```bash
> sudo lsof +f -- /var/log/myapp
> # or
> sudo fuser -km /var/log/myapp
> sudo umount /var/log/myapp
> ```

### 21.5 Detach the loop device

```bash
# What it does: Detaches the loop device associated with our image file.
# Why we run it: Release the loop device so we can remove the image file.

sudo losetup -d /dev/loop0 2>/dev/null || true
# Note: The loop device number may vary. Check with:
# losetup -a | grep myapp-fs.img
# Then detach the specific device.
```

### 21.6 Remove the backing image file

```bash
# What it does: Deletes the 500 MB image file.
# Why we run it: Free up the space on the real root filesystem.

sudo rm -f /tmp/myapp-fs.img
```

### 21.7 Remove the demo directory

```bash
# What it does: Removes the demo mount point and log directory.
# Why we run it: Clean up the directory we created.

sudo rm -rf /var/log/myapp
```

### 21.8 Remove the demo scripts

```bash
# What it does: Removes the log generator scripts.
# Why we run it: Clean up the scripts we created.

sudo rm -f /usr/local/bin/myapp-loggen.sh
sudo rm -f /usr/local/bin/myapp-loggen-fast.sh
sudo rm -f /usr/local/bin/myapp-loggen-reopen.sh
sudo rm -f /var/run/myapp-reopen.pid
```

### 21.9 Verify cleanup

```bash
# What it does: Verifies all demo artifacts are removed.
# Why we run it: Confirm the VM is restored to its original state.

echo "=== Checking mount ==="
mount | grep myapp || echo "No myapp mount (good)"

echo "=== Checking loop devices ==="
losetup -a | grep myapp || echo "No myapp loop device (good)"

echo "=== Checking image file ==="
ls -la /tmp/myapp-fs.img 2>/dev/null || echo "Image file removed (good)"

echo "=== Checking demo directory ==="
ls -la /var/log/myapp 2>/dev/null || echo "Demo directory removed (good)"

echo "=== Checking logrotate config ==="
ls -la /etc/logrotate.d/myapp 2>/dev/null || echo "Logrotate config removed (good)"

echo "=== Checking demo scripts ==="
ls -la /usr/local/bin/myapp-loggen*.sh 2>/dev/null || echo "Demo scripts removed (good)"

echo "=== Checking reopen PID file ==="
ls -la /var/run/myapp-reopen.pid 2>/dev/null || echo "Reopen PID file removed (good)"

echo "=== Checking reopen logrotate config ==="
ls -la /etc/logrotate.d/myapp-reopen 2>/dev/null || echo "Reopen logrotate config removed (good)"

echo "=== Checking root filesystem ==="
df -h /
```

**Expected output (example):**
```
=== Checking mount ===
No myapp mount (good)
=== Checking loop devices ===
No myapp loop device (good)
=== Checking image file ===
Image file removed (good)
=== Checking demo directory ===
Demo directory removed (good)
=== Checking logrotate config ===
Logrotate config removed (good)
=== Checking demo scripts removed (good)
=== Checking reopen PID file removed (good)
=== Checking reopen logrotate config removed (good)
=== Checking root filesystem ===
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        20G   8.2G   11G  44% /
```

**Conclusion:** The VM is restored to its original state. All demo artifacts have been removed.

---

## 22. Hashtags

```
#Linux #SRE #Logrotate #LinuxTroubleshooting #DevOps #SysAdmin #LinuxLogs #DiskFull #IncidentResponse #SiteReliabilityEngineering #Ubuntu #Proxmox #LinuxAdministration #LogManagement #NoSpaceLeftOnDevice
```

---

## Appendix A: Quick Command Reference

| Command | Purpose |
|---------|---------|
| `df -h` | Check filesystem storage capacity (bytes) |
| `df -i` | Check filesystem inode capacity (file slots) |
| `du -xhd1 <dir> \| sort -h` | Find which directories use the most space |
| `find <dir> -type f -size +100M -ls` | Find large files |
| `lsof +L1` | Find deleted-but-open files |
| `lsof \| grep deleted` | Alternative: find deleted-but-open files |
| `logrotate -d <config>` | Dry-run logrotate (debug mode) |
| `logrotate -f <config>` | Force logrotate rotation |
| `systemctl status logrotate.timer` | Check logrotate scheduler |
| `systemctl list-timers \| grep logrotate` | Check logrotate schedule |
| `: > <file>` | Truncate a file to zero bytes in place |
| `: > /proc/<pid>/fd/<n>` | Truncate a deleted-but-open file via /proc |
| `mount -o loop <image> <mountpoint>` | Mount a loopback filesystem |
| `umount <mountpoint>` | Unmount a filesystem |
| `losetup -d <device>` | Detach a loop device |
| `kill -HUP <pid>` | Signal app to reopen log files (like Nginx USR1) |
| `trap <handler> HUP` | Make a bash script respond to SIGHUP |

---

## Appendix B: Complete Demo Logrotate Config (Good)

```
/var/log/myapp/app.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
```

## Appendix C: Complete Demo Logrotate Config (Bad — for comparison)

```
/var/log/myapp/app.log {
    daily
    rotate 100
    missingok
    notifempty
    copytruncate
}
```
(No `compress`, excessive retention — demonstrates that rotation alone doesn't solve disk usage.)

## Appendix D: Postrotate + Signal Config (Production-Style Reopen)

```
/var/log/myapp/app.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 ubuntu ubuntu
    postrotate
        kill -HUP $(cat /var/run/myapp-reopen.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
```
(No `copytruncate` — uses `postrotate` + `SIGHUP` to signal the app to reopen its log. This is the pattern Nginx uses with `kill -USR1`.)

---

*End of Lab Guide*
