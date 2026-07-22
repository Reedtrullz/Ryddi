# Ryddi

Local-first macOS disk space manager. Free, open source, zero dependencies.

- **Clean** — Find and delete caches, logs, and junk in one click
- **Offload** — Move large folders to cloud storage, free local space
- **Control** — Keep bloated programs (Colima, Xcode, Docker) from eating your disk

## Install

**[Download Ryddi-v0.8.0.pkg](https://github.com/Reedtrullz/Ryddi/releases/latest)** — double-click and follow the installer. Copies Ryddi to `/Applications`.

Requires macOS 14+.

Or build from source:

## Features

| Pillar | What it does |
|--------|-------------|
| Clean | Scans 23 cache/log/junk directories. Classifies with 34 rules. One-click move to Trash. Auto-selects safe items. |
| Offload | Detects Dropbox, Google Drive, iCloud, MEGA, OneDrive. Copies large local folders. Offers to delete originals after verification. |
| Control | Detects Colima, Xcode simulators, DerivedData, Docker, Trash. One-click shrink for safe ops. |

**Also:** auto-scan on launch, emergency mode (<10 GB free), copy-to-clipboard reclaim report, custom scan paths, menu bar status, Full Disk Access guidance, keyboard shortcuts (⌘1/2/3), VoiceOver labels.

## Build

```bash
swift build --scratch-path .build
swift test --scratch-path .build
```

No dependencies. MIT license. No telemetry.

## Privacy

Everything stays on your Mac. No uploads, no analytics, no remote analysis.
