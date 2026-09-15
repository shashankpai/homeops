# Learning: Practical Linux & SRE Troubleshooting

A collection of practical, hands-on episodes covering real production incidents, troubleshooting techniques, and SRE best practices.

Each episode is a complete package:
- **lab-guide.md** — executable runbook with step-by-step commands and expected output
- **storyboard.md** — visual guide with timestamps and on-screen text for video production
- **metadata.md** — YouTube metadata, hashtags, and episode description
- **narration.md** — full spoken narration (kept local, not in repo)

## Episodes

### Episode 01: When Logs Kill Servers — Logrotate Explained

A real disk-full incident investigation from symptom to prevention.

**Topics covered:**
- Application logs and uncontrolled growth
- Troubleshooting disk-full incidents (`df`, `du`, `find`, `lsof`)
- Logrotate configuration, rotation, compression, and retention
- The "deleted but still open" file phenomenon
- Inode exhaustion side-path
- copytruncate vs postrotate mechanisms
- Live log-reopen demo (signal-aware app with SIGHUP)
- Prevention and best practices

**Duration:** ~44 minutes

**Lab environment:** Ubuntu VM with isolated 500 MB loopback filesystem

See `01-when-logs-kill-servers/` for the complete episode package.

---

## Future Episodes

- Episode 02: [TBD]
- Episode 03: [TBD]
