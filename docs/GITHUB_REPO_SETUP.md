# Ryddi GitHub Repo Setup

Use this when creating the GitHub repository.

## Repository Name

```text
ryddi
```

## Short Description

```text
Local-first macOS disk reclaim assistant for developer and AI-agent bloat.
```

## Website

Leave blank until there is a release page or product page.

## Topics

```text
macos
swift
swiftui
disk-cleanup
developer-tools
codex
docker
colima
xcode
local-first
privacy
cli
cleanup
storage
```

## Social Preview Copy

```text
Ryddi helps you find, review, and safely reclaim developer and AI-agent disk bloat on macOS. It explains every finding, protects valuable state, and requires dry-run evidence before cleanup.
```

## About Section

Ryddi is a cautious macOS disk reclaim assistant for developer and AI-agent storage growth. It scans local disk usage, classifies findings by safety, explains evidence, checks active file handles, builds dry-run plans, and only then helps reclaim selected low-risk items.

It focuses on storage that commonly grows during modern development work: Codex caches and sessions, Docker/Colima state, Xcode build products, package-manager caches, browser caches, logs, temp directories, and app-support bloat.

Ryddi is local-first: no telemetry, no path upload, no cloud analysis.

## Suggested Pinned Tagline

```text
Review first. Reclaim safely.
```

## Initial Release Notes Draft

```markdown
## Ryddi 0.1.0

Initial MVP:

- Swift core scanner and rule engine
- CLI for scan, overview, status, permissions, active-handle review, report, receipts, plan, explain, execute, schedule, and holding-area operations
- SwiftUI app overview, review queues, detail view, dry run, confirmed reclaim, audit history, automation, and holding area
- Codex, Docker/Colima, Xcode, package-manager, browser-cache, temp, and large-file review rules
- Open-file guard and active-handle review with `lsof` process summaries
- Dry-run receipts and local audit store
- Markdown evidence and receipt report exports
- App-managed holding area with restore/expire workflow
- Permission advisor for readable/denied/missing scan coverage and Full Disk Access guidance
- Release-check workflow for unsigned developer preview artifacts

Known limits:

- unsigned local bundle unless built with `CODESIGN_IDENTITY`
- no Apple notarization unless Developer ID credentials are configured
- no richer first-run permission walkthrough yet
- no root helper or system-wide cleanup
```
