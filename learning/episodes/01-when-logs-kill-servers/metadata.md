# When Logs Kill Servers: Logrotate Explained with a Real Incident
## YouTube Metadata

---

## 24. YouTube Title Options

### Primary (recommended)

**When Logs Kill Servers: Logrotate Explained with a Real Incident**

### Alternatives

1. **I Deleted a Log File But Disk Space Didn't Come Back (Linux Surprise)**
   - Focuses on the surprise/twist element. High curiosity factor.

2. **The Linux Surprise Every SRE Needs to Know: Deleted Files That Don't Free Space**
   - Emphasizes the SRE angle and the counterintuitive behavior.

3. **Logrotate Explained: From Disk-Full Incident to Production Fix**
   - Clear, direct, search-friendly. Good for evergreen traffic.

4. **Why Your Linux Server Ran Out of Disk (And How Logrotate Fixes It)**
   - Problem-solution framing. Relatable to anyone who's been paged.

5. **No Space Left on Device: A Real SRE Incident Walkthrough**
   - Incident-response framing. Appeals to SRE/DevOps audience.

6. **Logrotate, lsof +L1, and the Deleted-File Surprise — Linux Troubleshooting**
   - Tool-focused. Good for search SEO on specific commands.

7. **When Disk Full Becomes Application Down: A Linux Log Incident**
   - Highlights the "storage problem = application outage" angle.

8. **Logrotate for SREs: Rotation, Compression, Retention & the lsof Surprise**
   - Comprehensive, covers all topics in the title.

### SEO Notes

- Primary keyword targets: `logrotate`, `linux disk full`, `no space left on device`, `lsof`, `sre troubleshooting`
- Secondary keywords: `log rotation`, `copytruncate`, `df vs du`, `inode exhaustion`, `deleted file still open`
- The title should ideally be under 70 characters for full YouTube display. The primary title is 64 characters — good.

---

## 25. Thumbnail Concept

### Thumbnail Design

**Layout:** Split-screen with contrast.

**Left side (60%):**
- Dark terminal background (#1e1e2e)
- A large red error message in monospace font: `No space left on device`
- Below it, a `df -h` output showing `Use% 95%` with the `95%` in large red text
- A red warning icon (triangle with exclamation mark)

**Right side (40%):**
- A question mark in a circle, large, yellow (#f9e2af)
- Below the question mark: `rm app.log` (in monospace, white)
- Below that: `df unchanged` with a red X
- The word "WHY?" in large bold red text

**Bottom banner:**
- Text: "Logrotate Explained" in white on a semi-transparent dark strip

**Overall mood:** Urgent, mysterious, technical. The viewer should think "Wait, deleting a file doesn't free space? I need to watch this."

### Alternative Thumbnail Concepts

**Concept B — Before/After:**
- Left: `95% full` in red with a full progress bar
- Right: `49% used` in green with a half-full progress bar
- Center arrow with "logrotate" label
- Bottom: "The fix that saved the server"

**Concept C — The Surprise:**
- Terminal showing `sudo rm app.log`
- Below: `df -h` showing unchanged disk usage
- Large text: "Space NOT freed!"
- Subtitle: "The Linux surprise every SRE needs to know"

**Concept D — Incident Response:**
- Top: "DISK FULL INCIDENT" in red
- Middle: A flowchart-style mini-diagram: `df → du → find → app.log`
- Bottom: "SRE Troubleshooting Walkthrough"

### Thumbnail Text Guidelines

- Keep text minimal — 3-5 words max on the thumbnail itself
- Use high contrast: white/yellow text on dark background
- Font: bold sans-serif (Inter Bold, Montserrat, or similar)
- Make the red error message the visual focal point
- Ensure readability at small sizes (mobile)

---

## 26. YouTube Description

### Full Description

```
When Logs Kill Servers: Logrotate Explained with a Real Incident

Your application is running. CPU is normal. Memory is normal. But users are seeing failures. The server filesystem is almost full. In this episode, we investigate a real production disk-full incident from symptom to root cause to fix to prevention — exactly like an SRE would during an on-call.

We cover:
• What application logs are and why they grow
• How uncontrolled log growth fills a Linux filesystem
• How to troubleshoot a disk-full incident (df, du, find, lsof)
• What logrotate actually does (rotation, compression, retention, deletion)
• How to configure logrotate with a real config
• What copytruncate means and its tradeoffs
• Why simply deleting a log file can sometimes NOT release disk space
• What "deleted but still open" means at the Linux file-descriptor level
• How to find deleted-but-open files with lsof +L1
• How to reclaim space without restarting the process (the /proc trick)
• Briefly: inode exhaustion and how it differs from storage exhaustion
• How Nginx coordinates log rotation in production
• Live demo: log reopen with SIGHUP (same mechanism as Nginx, without installing Nginx)
• How to design a sensible log-retention policy
• Complete troubleshooting checklist for disk-full incidents
• Prevention strategies for production systems

Everything is demonstrated on a safe, isolated 500 MB loopback filesystem on an Ubuntu VM running on Proxmox. No real filesystems are harmed.

⏱ Timestamps:
0:00  - Intro: The incident
1:30  - What is an application log?
3:30  - Reproducing log growth
6:00  - Creating the disk-full incident
7:30  - Starting the investigation (df)
8:30  - Inode exhaustion side-path (df -i)
10:00 - Finding the culprit (du, find)
11:00 - Root cause: uncontrolled log growth
12:30 - Introducing logrotate
14:30 - Creating the logrotate config
17:00 - Demonstrating logrotate
20:00 - Bad retention configuration demo
22:30 - Who runs logrotate? (systemd timer)
24:30 - THE SURPRISE: deleted file, disk space not freed
30:40 - copytruncate deep dive
33:30 - Nginx production log-reopen + live demo with lsof
38:00 - Complete troubleshooting checklist
40:00 - Prevention and best practices
42:30 - Cleanup and reset
44:00 - Recap and outro

🔗 Related episodes:
[Episode 02 — link when published]

🛠 Lab environment:
- Ubuntu 22.04/24.04 LTS VM on Proxmox
- 500 MB loopback ext4 filesystem (isolated, safe)
- All commands included in the lab guide

📋 Commands covered:
df -h, df -i, du, find, lsof +L1, logrotate -d, logrotate -f,
systemctl status logrotate.timer, mount -o loop, mkfs.ext4,
kill -HUP, trap HUP, /proc/<pid>/fd/<n> truncation,
postrotate/endscript, delaycompress

If this was helpful, subscribe for more practical Linux and SRE troubleshooting episodes!

#Linux #SRE #Logrotate #LinuxTroubleshooting #DevOps #SysAdmin
```

### Short Description (for YouTube Shorts / social media)

```
Your server is failing. CPU is fine. Memory is fine. The disk is full — and it's all because of one log file. Then you delete it... and the space doesn't come back. Here's why, and how logrotate fixes it permanently. 🐧🔧

Full episode: [link]
#Linux #SRE #Logrotate #DevOps
```

---

## 27. Hashtags

### Primary Hashtags (for YouTube description)

```
#Linux #SRE #Logrotate #LinuxTroubleshooting #DevOps #SysAdmin #LinuxLogs #DiskFull #IncidentResponse #SiteReliabilityEngineering #Ubuntu #Proxmox #LinuxAdministration #LogManagement #NoSpaceLeftOnDevice
```

### Additional Hashtags (for social media promotion)

```
#LinuxTips #CommandLine #SystemAdministration #Infrastructure #PlatformEngineering #Observability #LogManagement #ServerMaintenance #TechTutorial #LearnLinux #SRELife #OnCall #IncidentManagement #LinuxServer #DevOpsLife
```

### Hashtag Strategy

| Category | Hashtags | Purpose |
|----------|----------|---------|
| Core topic | `#Linux #Logrotate #LinuxTroubleshooting` | Primary search discovery |
| Audience | `#SRE #DevOps #SysAdmin #PlatformEngineering` | Target audience reach |
| Specific concepts | `#DiskFull #NoSpaceLeftOnDevice #LogManagement` | Niche search terms |
| Tools | `#Ubuntu #Proxmox` | Environment-specific discovery |
| Incident type | `#IncidentResponse #OnCall #SRELife` | Incident-response community |
| Broad reach | `#TechTutorial #LearnLinux #CommandLine` | General tech education |

### Platform-Specific Notes

- **YouTube:** Use 10-15 hashtags in the description. YouTube shows the first 3 above the title.
- **Twitter/X:** Use 2-3 hashtags per post for maximum engagement.
- **LinkedIn:** Use 3-5 hashtags. Focus on professional tags: `#SRE #DevOps #Linux #SiteReliabilityEngineering`
- **Reddit:** No hashtags. Post in r/linux, r/sysadmin, r/devops, r/sre with a descriptive title.

---

## Additional Metadata

### Category
Science & Technology → Software Tutorials

### Tags (YouTube backend, comma-separated)
```
logrotate, linux, sre, site reliability engineering, devops, sysadmin, linux troubleshooting, disk full, no space left on device, lsof, df, du, find, copytruncate, log rotation, log management, inode exhaustion, deleted file still open, lsof +L1, nginx log rotation, ubuntu, proxmox, linux administration, incident response, on call, production incident, log lifecycle, log retention, log compression, file descriptor, /proc filesystem
```

### Language
English

### Video Visibility
Public

### Recording Date
2026-09-15

### Series
Practical Linux/SRE Troubleshooting — Episode 01

### Estimated Duration
~45 minutes

### Content Rating
No sensitive content (educational technical content)

### Monetization
Eligible (educational, advertiser-friendly content)

### Captions/Subtitles
Provide .srt file with full narration. English captions required. Consider auto-translating to Spanish, Portuguese, French, German, Hindi.

---

*End of Metadata*
