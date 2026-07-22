# Ryddi

Local-first macOS disk space manager. Free, open source, zero dependencies.

- **Clean** — Find and delete caches, logs, and junk in one click
- **Offload** — Move large folders to cloud storage, free local space
- **Control** — Keep bloated programs (Colima, Xcode, Docker) from eating your disk

## Install

**[Download Ryddi-v0.8.1.pkg](https://github.com/Reedtrullz/Ryddi/releases/latest)** — double-click and follow the installer. Copies Ryddi to `/Applications`.

Requires macOS 14+. Signed and notarized.

Or build from source:

## Features

| Pillar | What it does |
|--------|-------------|
| Clean | Scans 23 cache/log/junk directories. Classifies with 34 rules. One-click move to Trash. Auto-selects safe items. |
| Offload | Detects Dropbox, Google Drive, iCloud, MEGA, OneDrive. Copies large local folders. Offers to delete originals after verification. |
| Control | Detects Colima, Xcode simulators, DerivedData, Docker, Trash. One-click shrink for safe ops. |
| Audit | Deep directory audit with 11 bloat categories, safety scoring, and impact ranking. |

**Also:** auto-scan on launch, emergency mode (<10 GB free), copy-to-clipboard reclaim report, custom scan paths, menu bar status, Full Disk Access guidance, keyboard shortcuts (⌘1/2/3/4), VoiceOver labels.

## Build

```bash
swift build --scratch-path .build
swift test --scratch-path .build
```

### Signed Release Build

```bash
export SIGNING_IDENTITY="Developer ID Application: Your Name"
export NOTARY_KEY_ID="your-key-id"
export NOTARY_ISSUER_ID="your-issuer-id"
./Scripts/build-installer.sh 0.8.1
```

No dependencies. MIT license. No telemetry.

## Privacy

Everything stays on your Mac. No uploads, no analytics, no remote analysis.
