# When Logs Kill Servers: Logrotate Explained with a Real Incident
## Full Visual Storyboard

> **Format:** For every major section — timestamp, spoken narration cue, terminal command, expected output, visual/animation suggestion, and on-screen text.
> **Designed for:** 16:9 YouTube technical video (not a corporate slide deck).

---

## Visual Style Guide

- **Terminal:** Dark background (e.g., #1e1e2e), monospace font (JetBrains Mono or Fira Code), syntax highlighting where possible.
- **Diagrams:** Clean ASCII-style or flat-design vector graphics on dark background. Use accent colors: green for healthy, yellow for warning, red for danger, blue for concepts.
- **On-screen text:** Minimal, high-contrast, sans-serif (Inter or similar). Key takeaways only — never duplicate the full narration.
- **Transitions:** Simple cuts or quick fades. No flashy effects. This is a technical video, not a vlog.
- **Pacing:** Let terminal commands and output breathe. Don't rush past evidence — the viewer needs time to read the output.

---

## Key Visual Sequences

These 5 visual sequences appear multiple times throughout the episode. They are the core visual vocabulary.

### Visual Sequence 1: Log Growth

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   Application                                   │
│       │                                         │
│       │ write()                                 │
│       ▼                                         │
│   ┌──────────┐                                 │
│   │ app.log  │  10 MB  ████░░░░░░░░  10%        │
│   └──────────┘                                 │
│       │                                         │
│       ▼                                         │
│   ┌──────────┐                                 │
│   │ app.log  │  100 MB ███████░░░░  60%        │
│   └──────────┘                                 │
│       │                                         │
│       ▼                                         │
│   ┌──────────┐                                 │
│   │ app.log  │  300 MB ██████████░  85%        │
│   └──────────┘                                 │
│       │                                         │
│       ▼                                         │
│   ┌──────────┐                                 │
│   │ app.log  │  500 MB ████████████ 100%       │
│   └──────────┘                                 │
│       │                                         │
│       ▼                                         │
│   ╔═══════════════════════════════╗             │
│   ║  NO SPACE LEFT ON DEVICE      ║             │
│   ╚═══════════════════════════════╝             │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Animation:** The progress bar fills up progressively. The percentage climbs. The file size number ticks up. When it hits 100%, the red "NO SPACE LEFT ON DEVICE" box flashes in.

---

### Visual Sequence 2: Troubleshooting Flow

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   ┌─────────┐                                   │
│   │   df    │  "How full is the warehouse?"     │
│   └────┬────┘                                   │
│        │                                         │
│        ▼                                         │
│   ┌─────────┐                                   │
│   │   du    │  "Which section uses the space?"  │
│   └────┬────┘                                   │
│        │                                         │
│        ▼                                         │
│   ┌─────────┐                                   │
│   │  find   │  "Which specific boxes are huge?" │
│   └────┬────┘                                   │
│        │                                         │
│        ▼                                         │
│   ┌─────────────────┐                           │
│   │  huge app.log   │  ← ROOT CAUSE FOUND       │
│   └─────────────────┘                           │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Animation:** Each box lights up in sequence as the narrator explains each tool. An arrow draws between them. The final "huge app.log" box glows red.

---

### Visual Sequence 3: Inode Side-Path (Brief)

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   df -h                    df -i                │
│   ┌──────────────┐        ┌──────────────┐       │
│   │ Storage      │        │ Inodes       │       │
│   │ blocks       │        │              │       │
│   │              │        │ File/object  │       │
│   │ DATA         │        │ capacity     │       │
│   │ capacity    │        │              │       │
│   └──────────────┘        └──────────────┘       │
│                                                 │
│   "You can have free GBs                        │
│    but no inodes."                              │
│                                                 │
│   ┌──────────────────────────────────┐          │
│   │  20 GB total  2 GB used  18 GB   │ ✓ free   │
│   │  Inodes: 100% used                │ ✗ FULL   │
│   │  → "No space left on device"     │          │
│   └──────────────────────────────────┘          │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Animation:** Keep this visual SHORT. Show both boxes side by side. The "18 GB free ✓" lights up green. The "Inodes 100% ✗" lights up red. Then cut back to the main investigation. Do not linger.

---

### Visual Sequence 4: Logrotate Lifecycle

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   ┌──────────┐                                  │
│   │ app.log  │  ← current, being written to    │
│   └────┬─────┘                                  │
│        │                                        │
│        │  rotation (daily)                      │
│        ▼                                        │
│   ┌──────────┐                                  │
│   │app.log.1 │  ← renamed, uncompressed briefly │
│   └────┬─────┘                                  │
│        │                                        │
│        │  compression (gzip)                    │
│        ▼                                        │
│   ┌────────────┐                                │
│   │app.log.1.gz│  ← compressed, much smaller    │
│   └────┬───────┘                                │
│        │                                        │
│        │  retention (keep 7)                     │
│        ▼                                        │
│   ┌────────────┐                                │
│   │app.log.7.gz│  ← oldest retained copy        │
│   └────┬───────┘                                │
│        │                                        │
│        │  next rotation                         │
│        ▼                                        │
│   ┌────────────┐                                │
│   │  DELETED   │  ← automatically removed       │
│   └────────────┘                                │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Animation:** Each step lights up in sequence. The file size shrinks dramatically at the compression step (show a size comparison: "100 MB → 8 MB"). At the deletion step, the oldest file fades out with a "poof" effect.

---

### Visual Sequence 5: Deleted-but-Open Surprise

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   $ rm app.log                                  │
│        │                                        │
│        ▼                                        │
│   ┌──────────────────┐                         │
│   │ filename gone ✓  │  ← ls shows nothing     │
│   └──────────────────┘                         │
│        │                                        │
│        ▼                                        │
│   ┌──────────────────┐                         │
│   │ df unchanged ✗   │  ← disk still full!     │
│   └──────────────────┘                         │
│        │                                        │
│        ▼                                        │
│   ┌─────────────────────────────┐               │
│   │ process still has FD open   │               │
│   │                             │               │
│   │  process                    │               │
│   │     │                        │               │
│   │     ▼                        │               │
│   │  file descriptor (open!)    │               │
│   │     │                        │               │
│   │     ▼                        │               │
│   │  deleted file (inode alive) │               │
│   │     │                        │               │
│   │     ▼                        │               │
│   │  disk blocks still occupied │               │
│   └─────────────────────────────┘               │
│        │                                        │
│        ▼                                        │
│   $ lsof +L1                                    │
│        │                                        │
│        ▼                                        │
│   ┌──────────────────────────┐                  │
│   │ ROOT CAUSE FOUND ✓       │                  │
│   │                          │                  │
│   │ myapp-logge 12350 ...     │                  │
│   │ .../app.log (deleted)     │                  │
│   └──────────────────────────┘                  │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Animation:** This is the dramatic moment. After `rm app.log`, show "filename gone ✓" in green. Then show "df unchanged ✗" in red with a question mark. Build suspense. Then reveal the process → fd → deleted file → disk blocks chain. Finally, `lsof +L1` reveals the answer with a green checkmark.

---

## Phase-by-Phase Storyboard

---

### Phase 1 — Intro / Hook (0:00 – 1:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 0:00 | "Imagine this: you get paged at 2 AM..." | — | — | Dark screen, slow fade in. Terminal window appears. | "When Logs Kill Servers" |
| 0:20 | "And then you see this:" | `df -h /var/log/myapp` | `Use% 95%` | Terminal output appears. Highlight `95%` in red. | "95% full" |
| 0:35 | "The filesystem is 95% full..." | — | — | Cut to host. Brief B-roll of CPU/memory meters showing normal. | "CPU: normal / Memory: normal / Disk: CRITICAL" |
| 0:50 | "In this episode, we're going to investigate..." | — | — | Episode title card. | "SYMPROM → EVIDENCE → ROOT CAUSE → FIX → PREVENTION" |
| 1:05 | "And then — a surprise..." | — | — | Teaser: quick flash of `lsof +L1` output and "df unchanged" with a question mark. | "A surprise..." |
| 1:20 | "Ubuntu VM on Proxmox. Safe, isolated 500 MB filesystem." | — | — | Architecture diagram: Proxmox → Ubuntu VM → Demo FS. | "Safe lab: 500 MB isolated filesystem" |

---

### Phase 2 — What Is an Application Log? (1:30 – 3:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 1:30 | "Logs are not magic. They're just files." | — | — | Simple diagram: Application → write() → app.log → Disk. | "A log is just a file." |
| 2:05 | "Let me show you what real log lines look like:" | `head -5 /var/log/myapp/app.log` | 5 log lines with timestamps, INFO/ERROR | Terminal output with syntax highlighting. Highlight "ERROR" in red. | "Every line = storage consumed" |
| 2:30 | "Every single line consumes storage..." | — | — | Notebook analogy animation: pages being added one by one, notebook growing. | "Like a notebook that never gets emptied" |
| 3:00 | "The problem isn't the application — it's the lifecycle." | — | — | Split screen: healthy app (green) vs growing log (red). | "The problem is the lifecycle" |

---

### Phase 3 — Reproduce Log Growth (3:30 – 6:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 3:30 | "I've set up a demo application..." | — | — | Show the loggen script briefly. | "Demo app: continuous log generator" |
| 3:48 | "Let me start it in the background:" | `nohup /usr/local/bin/myapp-loggen.sh > /dev/null 2>&1 &` | `PID: 12345` | Terminal command and PID output. | — |
| 4:00 | "Let's watch the log file grow:" | `ls -lh /var/log/myapp/app.log` | `1.2M` | First measurement. | "1.2 MB" |
| 4:15 | "Fifteen megabytes. It's growing." | `ls -lh /var/log/myapp/app.log` | `15M` | Second measurement, larger. | "15 MB" |
| 4:50 | "To speed this up..." | — | — | Visual Sequence 1: Log Growth animation. | "10 MB → 100 MB → 300 MB → 500 MB → FULL" |
| 5:10 | "Let's watch the filesystem fill up:" | `watch -n 2 'df -h /var/log/myapp && echo "---" && ls -lh /var/log/myapp/app.log'` | Updating output, % climbing | `watch` output updating live. Progress bar filling. | "Watch it fill..." |
| 5:40 | "95% full." | — | `Use% 95%` | Final watch output. `95%` highlighted in red. | "95% full — INCIDENT" |

---

### Phase 4 — Create the Disk-Full Incident (6:00 – 7:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 6:00 | "So here's our situation." | `df -h /var/log/myapp` | `95%` | Terminal output. | — |
| 6:22 | "Let me show you what happens at 100%:" | `echo "test write" > /var/log/myapp/test-write.txt` | `No space left on device` | Error message in red. | "No space left on device" |
| 6:45 | "It affects EVERYTHING that needs disk space." | — | — | Animation: icons for temp files, PID files, databases, uploads, caches — all showing red X. | "temp files / PID files / databases / uploads / caches — ALL FAIL" |
| 7:00 | "A storage problem becomes an application outage." | — | — | Full-screen text card. | "A storage problem = an application outage" |

---

### Phase 5 — Start the Investigation (7:30 – 11:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 7:30 | "We know the filesystem is almost full, but we don't yet know what's consuming it." | — | — | Visual Sequence 2: Troubleshooting Flow (first box: df). | "What's consuming the space?" |
| 7:45 | "The first tool we always reach for is df." | `df -h` | Multiple filesystems, loop0 at 95% | Terminal output. Highlight `/dev/loop0` row in red. | "df = how full is the warehouse?" |
| 8:25 | "There's one more way Linux can report 'No space left'..." | — | — | Transition to inode side-path. Visual Sequence 3 appears. | "But first: a side note on inodes" |
| 8:35 | "Linux filesystems track two different resources." | — | — | Visual Sequence 3: Inode Side-Path diagram. Two boxes: Storage blocks vs Inodes. | "Two resources: blocks + inodes" |
| 9:12 | "Let me show you:" | `df -i` | Inodes at 1% | Terminal output. Highlight `1%` in green. | "Inodes: 1% — not exhausted" |
| 9:25 | "Imagine: 18 GB free, but inodes at 100%..." | — | — | Visual: 18 GB free (green checkmark) vs Inodes 100% (red X). | "Free GBs but no inodes" |
| 9:55 | "In our case, inodes are fine. Back to the main investigation." | — | — | Quick transition back. Visual Sequence 3 fades out. | "Back to the investigation" |
| 10:00 | "du tells us which section of the warehouse is using the space." | `sudo du -sh /var/log/myapp` | `475M` | Terminal output. Visual Sequence 2: second box (du) lights up. | "du = which section?" |
| 10:27 | "Now let's see what's inside:" | `sudo du -ah /var/log/myapp \| sort -h` | `475M app.log` | Terminal output. | — |
| 10:48 | "Let me cross-reference with find:" | `sudo find /var/log/myapp -type f -size +100M -ls` | One file, 475 MB | Terminal output. Visual Sequence 2: third box (find) lights up. | "find = which specific files?" |
| 11:00 | "The huge box is our application log." | — | — | Visual Sequence 2: final box "huge app.log" glows red. | "ROOT CAUSE: app.log" |

---

### Phase 6 — Identify the Log as the Root Cause (11:00 – 12:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 11:00 | "Now we can connect the dots." | — | — | Full chain diagram appears, each link lighting up in sequence. | "Filesystem full → du → find → app.log → no lifecycle" |
| 11:05 | — | — | — | Diagram: `df -h → du → find → app.log → no rotation → ROOT CAUSE` | "ROOT CAUSE: Uncontrolled log growth" |
| 11:45 | "This is incredibly common in production." | — | — | Story animation: app deployed → works for weeks → disk fills up one day. | "Common in production: no logrotate = eventual disk full" |
| 12:00 | "That tool is logrotate." | — | — | Transition to logrotate section. Logo/icon for logrotate. | "The fix: logrotate" |

---

### Phase 7 — Introduce Logrotate (12:30 – 14:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 12:30 | "Logrotate is NOT the application logging system." | — | — | Split diagram: Application (creates logs) vs Logrotate (manages lifecycle). | "logrotate ≠ logging system" |
| 12:45 | — | — | — | Full diagram: App → app.log → logrotate → rotate + compress + retain + delete. | "logrotate manages the lifecycle" |
| 13:20 | "Without logrotate: grows → grows → DISK FULL" | — | — | Simple animation: file growing until red "DISK FULL". | "Without logrotate: no lifecycle" |
| 13:22 | "With logrotate:" | — | — | Visual Sequence 4: Logrotate Lifecycle animation begins. | "With logrotate: predictable lifecycle" |
| 13:50 | "Four concepts:" | — | — | Four icons appear in sequence: Rotate, Compress, Retain, Delete. | "Rotate / Compress / Retain / Delete" |
| 14:05 | "Compression: 100 MB → 8 MB" | — | — | Size comparison visual: large bar (100 MB) shrinks to small bar (8 MB). | "100 MB → 8 MB (12x reduction)" |

---

### Phase 8 — Create Logrotate Configuration (14:30 – 17:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 14:30 | "Configs live in /etc/logrotate.d/" | — | — | File tree: `/etc/logrotate.d/myapp` | "/etc/logrotate.d/myapp" |
| 14:40 | "Let's create the config:" | `sudo tee /etc/logrotate.d/myapp ...` | Config file content | Terminal with syntax-highlighted config. | — |
| 15:08 | "Let me explain every directive." | — | — | Each directive highlights as it's explained. | — |
| 15:08 | "daily" | — | — | Highlight `daily`. | "daily = rotate once per day" |
| 15:30 | "rotate 7" | — | — | Highlight `rotate 7`. | "rotate 7 = keep 7 generations" |
| 15:48 | "compress" | — | — | Highlight `compress`. | "compress = gzip rotated logs" |
| 16:05 | "missingok" | — | — | Highlight `missingok`. | "missingok = don't error if file missing" |
| 16:20 | "notifempty" | — | — | Highlight `notifempty`. | "notifempty = skip empty logs" |
| 16:30 | "copytruncate" | — | — | Highlight `copytruncate`. Preview of Phase 17. | "copytruncate = copy + truncate in place" |

---

### Phase 9 — Demonstrate Logrotate (17:00 – 20:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 17:00 | "Always dry-run first." | `sudo logrotate -d /etc/logrotate.d/myapp` | Debug output, "does not need rotating" | Terminal output. Highlight "does not need rotating". | "logrotate -d = debug/dry-run" |
| 17:55 | "Let's force a rotation:" | `sudo logrotate -f /etc/logrotate.d/myapp` | (silent) | Terminal command. | "logrotate -f = force rotation" |
| 18:08 | "Let's see what happened:" | `ls -lh /var/log/myapp/` | `app.log` (small) + `app.log.1.gz` (compressed) | Terminal output. Two files visible. | "app.log (fresh) + app.log.1.gz (compressed)" |
| 18:25 | "475 MB compressed to 35 MB!" | — | — | Size comparison: 475 MB → 35 MB. | "475 MB → 35 MB (13x compression!)" |
| 19:15 | "Let's force several more rotations:" | `for i in $(seq 1 8); do ... done` | 7 `.gz` files + current `app.log` | Terminal output showing 8 files. | "Retention: exactly 7 generations kept" |
| 19:58 | "Let's check the filesystem:" | `df -h /var/log/myapp` | `49%` | Terminal output. `49%` in green. | "95% → 49% ✓" |

---

### Phase 10 — Demonstrate Bad Retention (20:00 – 22:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 20:00 | "What happens when logrotate is configured BADLY?" | — | — | Warning icon. | "Bad config demo" |
| 20:18 | "rotate 100, no compress:" | `sudo tee /etc/logrotate.d/myapp ...` | Bad config content | Terminal with config. Highlight missing `compress` and `rotate 100` in red. | "rotate 100 + no compress = BAD" |
| 21:18 | "Let's rotate several times:" | `for i in $(seq 1 5); do ... done` | 5 uncompressed files, 80-90 MB each | Terminal output. No `.gz` extensions. | "No compression = full size" |
| 21:58 | "Let's check:" | `df -h /var/log/myapp` | `95%` | Terminal output. `95%` in red. | "95% full AGAIN!" |
| 22:10 | "Rotation alone did NOT solve the problem." | — | — | Comparison: good config (49%) vs bad config (95%). | "Rotation ≠ solution. You need all three." |
| 22:30 | "Restore the good config:" | `sudo tee /etc/logrotate.d/myapp ...` | Good config content | Terminal with restored config. | "Restored: rotate 7 + compress" |

---

### Phase 11 — Who Runs Logrotate? (22:30 – 24:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 22:30 | "When does logrotate actually run?" | — | — | Question mark animation. | "Who schedules logrotate?" |
| 22:42 | "No. Logrotate is not a daemon." | — | — | Diagram: systemd timer → logrotate → configs. | "logrotate = batch tool, not daemon" |
| 23:15 | "On Ubuntu, it's a systemd timer:" | `systemctl status logrotate.timer` | Timer active, daily | Terminal output. Highlight "Daily" and "active". | "systemd timer: daily at midnight" |
| 23:45 | "Let me show the timer list:" | `systemctl list-timers \| grep logrotate` | Next trigger: midnight | Terminal output. | — |
| 24:15 | "Our config sits alongside system configs:" | `ls /etc/logrotate.d/` | Multiple configs including `myapp` | Terminal output. Highlight `myapp`. | "/etc/logrotate.d/ — one file per app" |

---

### Phase 12 — The Surprise: Deleted-but-Open (24:30 – 30:40)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 24:30 | "This is the surprise that catches almost every engineer." | — | — | Dramatic transition. Darker background. | "THE SURPRISE" |
| 24:58 | "Let me show you exactly what I mean." | — | — | Visual Sequence 5 begins. | — |
| 25:05 | "Current state:" | `df -h /var/log/myapp && ls -lh /var/log/myapp/` | 300M used, app.log 280M | Terminal output. | "Before: 280 MB in app.log" |
| 25:32 | "Let's delete the log file:" | `sudo rm /var/log/myapp/app.log` | (silent) | Terminal command. | "$ rm app.log" |
| 25:40 | "The file is gone:" | `ls -lh /var/log/myapp/` | Only app.log.1.gz remains | Terminal output. | "Filename gone ✓" |
| 25:55 | "Now let's check the filesystem:" | `df -h /var/log/myapp` | Still 300M used, 63% | Terminal output. `63%` highlighted in red. | "df UNCHANGED ✗ — space NOT freed!" |
| 26:10 | "Wait. The file is gone. But disk usage is UNCHANGED." | — | — | Pause for dramatic effect. Big question mark on screen. | "280 MB deleted. 0 MB freed. Why??" |
| 26:28 | "Here's what's happening." | — | — | Visual Sequence 5: process → fd → deleted file → disk blocks diagram. | "Deleting a name ≠ freeing the data" |
| 27:10 | "The filename is like the label on a storage box." | — | — | Analogy animation: box with label, label removed, person still using box. | "Label removed ≠ box empty" |
| 27:45 | "How do we find this? lsof +L1." | — | — | Command preview. | "lsof +L1 = find deleted-but-open files" |
| 28:00 | "Let's run it:" | `sudo lsof +L1` | Shows myapp-logge, PID, fd 3w, 280M, (deleted) | Terminal output. Highlight `(deleted)` and `280M`. | "FOUND: 280 MB held by PID 12350" |
| 28:20 | "Let me break down what we're seeing." | — | — | Annotated lsof output: COMMAND, PID, FD, SIZE, NLINK, NAME each labeled. | "FD 3w = descriptor 3, write mode" |
| 29:40 | "There's a trick. Truncate through /proc." | — | — | Diagram: /proc/PID/fd/3 → truncate → space freed. | "Truncate via /proc — no restart needed" |
| 29:42 | "Find the file descriptor:" | `ls -la /proc/$LOGGEN_PID/fd/ \| grep deleted` | fd 3 → app.log (deleted) | Terminal output. | — |
| 30:02 | "Truncate it:" | `sudo sh -c ': > /proc/'$LOGGEN_PID'/fd/3'` | (silent) | Terminal command. | — |
| 30:12 | "Let's check:" | `df -h /var/log/myapp` | 5% — space freed! | Terminal output. `5%` in green. | "280 MB RECLAIMED ✓ — no restart!" |
| 30:35 | "The real lesson: don't just rm a log file." | — | — | Three options: copytruncate, postrotate, truncate in place. | "Use logrotate, not rm" |

---

### Phase 13 — copytruncate Deep Dive (30:40 – 33:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 30:40 | "Let's talk about copytruncate in detail." | — | — | Section title card. | "copytruncate Deep Dive" |
| 30:50 | "What happens WITHOUT copytruncate?" | — | — | Diagram: app moves app.log → app.log.1, app still writes to app.log.1, new app.log is empty. | "Without copytruncate: app writes to wrong file" |
| 31:00 | — | — | — | Diagram animation: fd points to inode 100, file renamed to app.log.1, new app.log is inode 200. App still at inode 100. | "fd follows the inode, not the name" |
| 31:35 | "With copytruncate:" | — | — | Diagram: copy content to app.log.1, truncate original to 0, same inode. App keeps writing. | "With copytruncate: copy + truncate in place" |
| 31:55 | — | — | — | Diagram animation: fd → inode 100, content copied to app.log.1, inode 100 truncated to 0. App continues at inode 100. | "Same inode, same fd, no signal needed" |
| 32:35 | "The tradeoff: small race window." | — | — | Animation: brief window between copy and truncate where log lines could be lost. | "Tradeoff: small race window, potential log loss" |
| 33:05 | "Not universally best. For apps that support reopening..." | — | — | Transition to Nginx section. | "For Nginx etc: postrotate is cleaner" |

---

### Phase 14 — Nginx Production Example + Live Reopen Demo (33:30 – 37:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 33:30 | "The preferred model: rotate + signal app to reopen." | — | — | Section title card. | "Production Log Reopen: Nginx" |
| 33:48 | "Here's a representative Nginx config:" | `cat /etc/logrotate.d/nginx` | Config with postrotate | Terminal with syntax-highlighted config. | — |
| 34:15 | "The key part: postrotate." | — | — | Highlight `postrotate ... endscript` block. | "postrotate = script after rotation" |
| 34:35 | "kill -USR1 tells Nginx to reopen logs." | — | — | Diagram: signal flow: logrotate → USR1 → Nginx → close old fd → open new app.log. | "USR1 = Nginx reopens log files" |
| 34:55 | — | — | — | Full numbered diagram: 1. rotate, 2. move, 3. create new, 4. signal, 5. close old, 6. open new, 7. continue. | "rotate + reopen = clean lifecycle" |
| 35:20 | "delaycompress: don't compress immediately." | — | — | Highlight `delaycompress`. Timeline: app.log.1 (uncompressed) → next rotation → app.log.2.gz. | "delaycompress = compress on next cycle" |
| 35:50 | "We don't need Nginx — let's see this live with our demo app." | — | — | Transition: "Same mechanism, different signal." | "Live Demo: Log Reopen Without Nginx" |
| 36:00 | "Start the signal-aware app:" | `nohup myapp-loggen-reopen.sh & ...` | PID, then tail shows logs | Terminal: start app, write PID, verify logs. | "Signal-aware app: reopens on SIGHUP" |
| 36:15 | "Force a rotation:" | `sudo logrotate -f /etc/logrotate.d/myapp-reopen` | (silent) | Terminal command. | "Rotate + send SIGHUP" |
| 36:25 | "Let's see what happened:" | `ls -lh /var/log/myapp/ && tail ...` | app.log has "reopened" marker + new lines; app.log.1 has old lines | Terminal output. Split view: new app.log vs old app.log.1. | "app.log: NEW lines ✓ / app.log.1: OLD lines ✓" |
| 36:35 | "The app caught the signal and reopened." | — | — | Diagram: SIGHUP → trap → exec >> app.log → new fd. | "SIGHUP → close old fd → open new app.log" |
| 36:50 | "Now WITHOUT the signal — the problem:" | Switch to non-signal app, rotate again | app.log EMPTY, app.log.1 still growing | Terminal output. `app.log` size = 0 in red. `app.log.1` growing in red. | "WITHOUT signal: app.log = 0 bytes ✗ / app.log.1 still growing ✗" |
| 37:00 | "Rotate + signal = clean. No race window, no lost lines." | — | — | Comparison: copytruncate vs postrotate vs no-reopen. | "copytruncate / postrotate+signal / (broken: no signal)" |

---

### Phase 15 — Troubleshooting Checklist (37:00 – 39:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 37:00 | "The complete troubleshooting flow." | — | — | Full checklist diagram appears, building step by step. | "SRE Disk-Full Checklist" |
| 37:10 | — | — | — | Diagram: DISK ALERT → df -h → df -i → du → find → is it a log? → logrotate/lsof → verify → prevention. | — |
| 38:00 | "Step one: df -h, then df -i." | — | — | First two boxes light up. | "1. df -h (bytes) + df -i (inodes)" |
| 38:20 | "Step two: du, then find." | — | — | Next two boxes light up. | "2. du (directories) + find (large files)" |
| 38:30 | "Step three: is it a log? Check logrotate." | — | — | Branch: YES → logrotate config. NO → other consumers. | "3. Log? → check logrotate / Other? → investigate" |
| 38:55 | "Step four: lsof +L1. Fix. Verify. Prevent." | — | — | Final boxes light up. | "4. lsof +L1 → fix → verify → prevent" |

---

### Phase 16 — Prevention (39:00 – 41:30)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 39:00 | "The best incident is the one that never happens." | — | — | Section title card. | "Prevention" |
| 39:05 | "Every app needs a logrotate config." | — | — | Checklist item 1 appears. | "1. Logrotate config for every app" |
| 39:25 | "Always compress." | — | — | Checklist item 2. Size comparison: 100 MB → 8 MB. | "2. Always compress (10-20x reduction)" |
| 39:40 | "Sensible retention." | — | — | Checklist item 3. Formula: volume × retention × compression. | "3. Sensible retention (based on capacity + needs)" |
| 39:55 | "Use postrotate for apps that support it." | — | — | Checklist item 4. | "4. postrotate > copytruncate (when supported)" |
| 40:10 | "Monitor disk. Alert at 80% and 90%." | — | — | Checklist item 5. Gauge animation: green → yellow (80%) → red (90%). | "5. Alert at 80% / 90% — never hit 100%" |
| 40:25 | "Centralized logging for large fleets." | — | — | Checklist item 6. Diagram: multiple hosts → centralized log system. | "6. Centralized logging (ELK, Loki, Grafana)" |
| 40:45 | "Container logs are different." | — | — | Checklist item 7. Docker logo. | "7. Container logs ≠ host logs (use log driver rotation)" |
| 41:05 | "Config management for fleet consistency." | — | — | Checklist item 8. Ansible logo. | "8. Ansible/Puppet/Chef for fleet-wide consistency" |
| 41:20 | "Review log volume after app changes." | — | — | Checklist item 9. | "9. Review log volume after deployments" |
| 41:30 | "The golden rule: predictable log lifecycle." | — | — | Full-screen card. | "GOAL: predictable log lifecycle — not just 'delete logs'" |

---

### Phase 17 — Cleanup / Reset (41:30 – 43:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 41:30 | "Let's clean up the demo." | — | — | Warning banner. | "⚠ DESTRUCTIVE COMMANDS — cleanup only" |
| 41:42 | "Stop, remove, unmount, delete:" | Series of cleanup commands | Various outputs | Terminal commands in sequence. Each labeled. | "Stop generator / Remove configs / Unmount / Remove image / Remove scripts + PID" |
| 42:32 | "Verify everything is gone:" | Verification commands | All "good" messages | Terminal output. All checks show "(good)". | "VM restored to original state ✓" |

---

### Outro (43:00 – 44:00)

| Time | Narration Cue | Terminal | Expected Output | Visual | On-Screen Text |
|------|---------------|----------|-----------------|--------|----------------|
| 43:00 | "Let's recap." | — | — | Recap card. | "Recap" |
| 43:05 | "df → du → find → app.log" | — | — | Visual Sequence 2 (troubleshooting flow) replays briefly. | "Investigated: df → du → find → root cause" |
| 43:25 | "logrotate: rotate + compress + retain" | — | — | Visual Sequence 4 (logrotate lifecycle) replays briefly. | "Fixed: logrotate (95% → 49%)" |
| 43:40 | "Bad config: rotation alone isn't enough." | — | — | Brief flash of bad config comparison. | "Bad config: rotation ≠ solution" |
| 43:50 | "Log reopen live: signal-aware app." | — | — | Brief flash of the reopen demo: SIGHUP → new app.log. | "Log reopen: SIGHUP → new fd → clean" |
| 44:00 | "Surprise: deleted file, space not freed. lsof +L1." | — | — | Visual Sequence 5 (deleted-but-open) replays briefly. | "Surprise: lsof +L1 — deleted but open" |
| 44:00 | "Subscribe for more. See you next time." | — | — | End card. Subscribe button. Links to next episode. | "Subscribe / Next: [episode 02 title]" |

---

## Diagram Library

All diagrams in this storyboard are designed to be rendered as either:
1. **ASCII art** in the terminal (for a retro, authentic SRE feel), or
2. **Flat-design vector graphics** (for a polished YouTube look), or
3. **Excalidraw-style hand-drawn diagrams** (for a friendly, educational feel).

Choose one style and use it consistently throughout the episode.

### Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Background | #1e1e2e | Terminal / diagram background |
| Green | #a6e3a1 | Healthy, success, fixed |
| Yellow | #f9e2af | Warning, caution |
| Red | #f38ba8 | Danger, error, full |
| Blue | #89b4fa | Concepts, information |
| Purple | #cba6f7 | Highlights, emphasis |
| Text | #cdd6f4 | Primary text |
| Subtext | #a6adc8 | Secondary text |

---

*End of Storyboard*
