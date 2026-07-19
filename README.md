# Ryddi

Local-first macOS disk space manager. Three things:

- **Clean** — Find and delete caches, logs, and junk in one click
- **Offload** — Move large folders to cloud storage, free local space
- **Control** — Keep bloated programs (Colima, Xcode) from eating your disk

## Build

```bash
swift build --scratch-path .build
swift test --scratch-path .build
```

Runs on macOS 14+. No dependencies.

## Why

Modern Macs accumulate bloat: caches, old downloads, package-manager stores, VM disks, build artifacts. Some of it is safe to delete. Some needs review. Some you want to offload to cloud. Ryddi shows you what's what and lets you act.

## Privacy

No telemetry, no uploads, no remote analysis. Everything stays on your Mac. MIT license.
