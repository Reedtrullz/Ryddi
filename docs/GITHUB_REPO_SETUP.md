# Ryddi GitHub Repo Setup

Use this when creating the GitHub repository.

## Repository Name

```text
ryddi
```

## Short Description

```text
Local-first macOS disk reclaim assistant for general cleanup with developer-first rules.
```

## Website

Leave blank until there is a release page or product page.

## Topics

```text
macos
swift
swiftui
mac-cleaner
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
Ryddi helps you find, review, and safely reclaim Mac disk bloat, with developer and AI-agent cleanup rules being perfected first. It explains every finding, protects valuable state, supports portable local policy, and requires dry-run evidence before cleanup.
```

## About Section

Ryddi is a cautious macOS disk reclaim assistant for general cleanup, with developer and AI-agent storage growth as the first deep rule pack. It scans local disk usage, classifies findings by safety, explains evidence, checks active file handles, builds dry-run plans, and only then helps reclaim selected low-risk items.

It can review ordinary Mac cleanup roots such as Downloads, personal folders, user caches, logs, app support, attachments, backups, and Trash. Its current depth is strongest for storage that commonly grows during modern development work: Codex, Claude, Cursor, Windsurf, and Ollama storage; Docker/Colima state; Xcode build products; package-manager caches; browser caches; logs; temp directories; and app-support bloat.

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
- CLI for scan scope presets, built-in scope templates, saved scope sets, scan, overview, review queues, large/old review, disk drill-down, bundled rule catalog, status, permissions, active-handle review, apps-and-leftovers review, app uninstall preview/execution receipts, AI-agent storage review, report, history/growth reports, plan/plans, receipts, recovery, explain, execute, schedule, and holding-area operations
- SwiftUI app overview, visual map, disk drill-down, rule catalog, review queues, Large & Old Files, detail view, Apps & Leftovers, app uninstall preview/execution receipts, AI Agent Storage, dry run, confirmed reclaim, audit history, recovery center, automation, and holding area
- Codex, Docker/Colima, Xcode, package-manager, browser-cache, temp, and large-file review rules
- AI-agent storage buckets and retention profiles that separate reclaimable cache, old-history compression review, protected state, quit-first data, and manual review
- Open-file guard and active-handle review with `lsof` process summaries
- Dry-run receipts and local audit store
- Markdown evidence, growth, plan, and receipt report exports with path privacy controls
- Saved scope sets for repeatable general cleanup, project review, or developer maintenance scan roots
- Local path protections/exclusions with versioned JSON export, merge import, and explicit replace import
- Local user rule-pack preview/import/export in CLI and app for custom review, preserve, and never-touch signals; user rules are opt-in per scan and cannot grant cleanup actions
- App-managed holding area with restore/expire workflow
- Recovery Center for app-held restores and receipt-based guidance
- Permission advisor and first-run walkthrough for readable/denied/missing scan coverage and Full Disk Access guidance
- Release-check workflow for unsigned developer preview artifacts

Known limits:

- unsigned local bundle unless built with `CODESIGN_IDENTITY`
- no Apple notarization unless Developer ID credentials are configured
- no screenshots/GIFs for the first-run permission walkthrough yet
- no root helper or system-wide cleanup
- app uninstall execution can move only the selected app bundle to Trash after dry run and confirmation; related app support files stay review-only
```
