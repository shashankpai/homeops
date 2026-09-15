# Episode 01: Demo Flow Mapping

## Narration Phase → Lab-Guide Section Mapping

This document maps each narration phase to the corresponding lab-guide sections that should be displayed on screen during the video.

| Narration Phase | Time | Lab-Guide Sections | What to Show | Notes |
|---|---|---|---|---|
| **Phase 1: Intro / Hook** | 0:00–1:30 | — | Title card, no lab yet | Hook the viewer with the problem |
| **Phase 2: What Is an Application Log?** | 1:30–3:30 | 6.1 | Diagram: Application → write() → /var/log/myapp/app.log → Disk | Conceptual, no commands |
| **Phase 3: Reproduce Log Growth** | 3:30–6:00 | 5 (setup), 6.2–6.3 | Run commands: create mount, create log generator, test it | First live demo commands |
| **Phase 4: Create the Disk-Full Incident** | 6:00–7:30 | 7.1–7.2 | Start log generator, watch growth with `ls -lh` | Show the problem in action |
| **Phase 5: Start the Investigation** | 7:30–11:00 | 8–10 | Run `df -h`, `df -i`, `du`, `find` — troubleshooting flow | Core investigation techniques |
| **Phase 6: Identify the Log as Root Cause** | 11:00–12:30 | 10.5 | Show root cause identified | Conclusion of investigation |
| **Phase 7: Introduce Logrotate** | 12:30–14:30 | 11 | Explain logrotate concepts (no commands yet) | Conceptual explanation |
| **Phase 8: Create Logrotate Configuration** | 14:30–17:00 | 12.1–12.3 | Create logrotate config, show the directives | First logrotate config |
| **Phase 9: Demonstrate Logrotate** | 17:00–20:00 | 13.1–13.6 | Run logrotate demo: dry-run, force rotation, observe | Live rotation demo |
| **Phase 10: Demonstrate Bad Retention** | 20:00–22:30 | 14.1–14.4 | Bad config demo: rotate with bad retention, show problem | Teach what NOT to do |
| **Phase 11: Who Runs Logrotate?** | 22:30–24:30 | 15.1–15.4 | Show scheduler: `systemctl status logrotate.timer` | Explain automation |
| **Phase 12: The Surprise: Deleted-but-Open** | 24:30–30:40 | 16.1–16.9 | Deleted-but-open demo: delete file, check `lsof +L1`, reclaim space | The "aha!" moment |
| **Phase 13: copytruncate Deep Dive** | 30:40–33:30 | 17 | Explain copytruncate (conceptual, no live demo) | Alternative approach |
| **Phase 14: Production Log Reopen + Live Demo** | 33:30–37:00 | 18.6.1–18.6.6 | **Live reopen demo**: create signal-aware app, rotate, show reopen, contrast | NEW: Signal-aware app demo |
| **Phase 15: Troubleshooting Checklist** | 37:00–39:00 | — | Show troubleshooting checklist diagram (no lab) | Summary diagram |
| **Phase 16: Prevention & Best Practices** | 39:00–41:30 | — | Prevention best practices (no lab) | Conceptual |
| **Phase 17: Cleanup / Reset** | 41:30–43:00 | 21 | Run cleanup commands | Restore VM to original state |
| **Outro** | 43:00–44:00 | — | Recap, subscribe card | End screen |

## Key Demo Sections

### Setup Phase (Phase 3)
- **Lab sections:** 5 (filesystem setup) + 6.2–6.3 (create & test log generator)
- **Duration:** ~2.5 minutes of screen time
- **Key commands:** `dd`, `mkfs.ext4`, `mount`, `tee`, `chmod`
- **Expected output:** Loopback filesystem mounted, log generator installed and tested

### Incident Phase (Phases 4–5)
- **Lab sections:** 7 (start generator) + 8–10 (investigation)
- **Duration:** ~4 minutes of screen time
- **Key commands:** `df -h`, `df -i`, `du`, `find`, `ls -lh`
- **Expected output:** Filesystem 95% full, root cause identified as `/var/log/myapp/app.log`

### Fix Phase (Phases 8–9)
- **Lab sections:** 12 (create config) + 13 (demo rotation)
- **Duration:** ~3 minutes of screen time
- **Key commands:** `tee`, `logrotate -d`, `logrotate -f`, `ls -lh`, `tail`
- **Expected output:** Disk usage drops from 95% to 49%, old logs compressed and deleted

### Bad Config Demo (Phase 10)
- **Lab sections:** 14 (bad retention demo)
- **Duration:** ~2.5 minutes of screen time
- **Key commands:** `tee`, `logrotate -f`, `du -xhd1`
- **Expected output:** Disk usage stays high because retention is excessive and compression is disabled

### Scheduler (Phase 11)
- **Lab sections:** 15 (systemd timer)
- **Duration:** ~2 minutes of screen time
- **Key commands:** `systemctl status logrotate.timer`, `cat /etc/logrotate.conf`, `ls /etc/logrotate.d/`
- **Expected output:** Show that logrotate runs daily via systemd, not continuously

### Surprise: Deleted-but-Open (Phase 12)
- **Lab sections:** 16 (lsof demo)
- **Duration:** ~6 minutes of screen time
- **Key commands:** `rm`, `df -h`, `lsof +L1`, `truncate`, `/proc/<pid>/fd/<n>`
- **Expected output:** Deleted file still holds space, `lsof +L1` finds it, `/proc` trick reclaims space

### Live Reopen Demo (Phase 14) ← **NEW**
- **Lab sections:** 18.6.1–18.6.6 (signal-aware app)
- **Duration:** ~3.5 minutes of screen time
- **Key commands:** `tee`, `nohup`, `logrotate -f`, `tail`, `kill -HUP`
- **Expected output:** 
  - Signal-aware app: `app.log` has "log reopened" marker + new lines, `app.log.1` has old lines
  - Non-signal app: `app.log` is empty (0 bytes), `app.log.1` still growing
- **What makes it special:** Shows the same mechanism as Nginx without installing Nginx

### Cleanup (Phase 17)
- **Lab sections:** 21 (cleanup commands)
- **Duration:** ~1.5 minutes of screen time
- **Key commands:** `pkill`, `rm`, `umount`, `losetup -d`
- **Expected output:** All demo files and mounts removed, VM restored to original state

## Notes for Video Production

### Narration vs Lab-Guide
1. **Narration is conversational** — it doesn't mention every command. Use the lab-guide as the authoritative source for what to run.
2. **Lab-guide has detailed comments** — "What it does" and "Why we run it" — use these for on-screen text or voiceover.
3. **Expected outputs are in the lab-guide** — match these when recording to ensure accuracy.

### Demo Pacing
- **Total runtime:** ~44 minutes
- **Setup:** ~2.5 min (Phase 3)
- **Incident & Investigation:** ~4 min (Phases 4–5)
- **Logrotate basics:** ~5 min (Phases 7–9)
- **Bad config & scheduler:** ~4.5 min (Phases 10–11)
- **Surprise moment:** ~6 min (Phase 12)
- **copytruncate explanation:** ~3 min (Phase 13)
- **Live reopen demo:** ~3.5 min (Phase 14) ← **Highlight**
- **Checklist & prevention:** ~4.5 min (Phases 15–16)
- **Cleanup:** ~1.5 min (Phase 17)

### The Live Reopen Demo (Phase 14) is the Highlight
- It's the only place where the signal-aware app (`myapp-loggen-reopen.sh`) is used
- Everything before uses the standard log generator (`myapp-loggen.sh` or `myapp-loggen-fast.sh`)
- The contrast between signal-aware and non-signal-aware apps is the "aha!" moment
- Make sure to clearly label which app is running at each step

### Syncing Narration & Lab-Guide
If you update the narration timestamps, update this table accordingly. The lab-guide sections should remain stable — they're the "source of truth" for what commands to run.

## Quick Reference: Which Script to Use

| Phase | Script | Why |
|---|---|---|
| Phase 3 | `myapp-loggen.sh` | Standard generator, test it briefly |
| Phase 4–7 | `myapp-loggen-fast.sh` | Fast version for demo pacing (no delay between logs) |
| Phase 12 | `myapp-loggen.sh` (stopped) | For the deleted-but-open demo |
| Phase 14 (first part) | `myapp-loggen-reopen.sh` | Signal-aware app, shows successful reopen |
| Phase 14 (contrast) | `myapp-loggen-fast.sh` | Non-signal app, shows the problem |

---

**Generated with [Devin](https://devin.ai)**
