# Ryddi

[![CI](https://github.com/Reedtrullz/Ryddi/actions/workflows/ci.yml/badge.svg)](https://github.com/Reedtrullz/Ryddi/actions/workflows/ci.yml)

Ryddi is a local-first macOS disk reclaim assistant for developer and AI-agent storage growth.

It is named from Norwegian **ryddig** / **rydde**: tidy, orderly, to clean up. The goal is not to be a scary one-click cleaner. Ryddi scans, explains, plans, and only then helps you reclaim space with receipts and guardrails.

## About

Modern developer Macs accumulate a strange kind of bloat: Codex sessions and caches, Docker and Colima VM data, Xcode build products, package-manager caches, browser clones, logs, temp directories, and app-support leftovers. Some of that is pure trash. Some of it is valuable history. Some of it is dangerous to touch directly.

Ryddi treats cleanup as evidence review:

- map where space is going;
- classify each finding by safety;
- explain why it matched;
- check active file handles before action;
- build a dry-run reclaim plan;
- require confirmation before destructive cleanup;
- keep audit receipts locally;
- preserve user data, credentials, sessions, profiles, creative assets, and VM/container state by default.

## Current Status

Ryddi is an early MVP. It has a shared Swift core, a CLI, and a SwiftUI app shell. The safest path today is scan, review, dry run, then reclaim only selected auto-safe items.

No telemetry, path uploads, remote analysis, root helper, or Mac App Store sandboxing in v1.

See [PRIVACY.md](PRIVACY.md) for the local-only privacy model and what Ryddi should never touch automatically.

## What It Handles

- top-offender overview with category, safety, age, logical size, and allocated size
- proportional visual map nodes by category, using non-overlapping allocated-size accounting
- local scan history snapshots and category growth deltas
- menu bar disk-pressure status with report-only scan shortcut
- permission/degraded-scan coverage and APFS accounting notes
- Finder, Quick Look, Terminal, and copy-path actions in the app
- local user protections and exclusions for paths Ryddi should preserve or ignore
- large-file and old-file review signals
- duplicate-file review with local content hashing, explicit CLI paths, and no automatic cleanup
- apps-and-leftovers review for installed app support files and heuristic orphan candidates
- Codex cache/temp/log/session policy
- Docker and Colima reporting with native-tool guidance
- read-only Docker/Colima inventory for storage buckets, images, containers, volumes, profiles, and command outcomes
- native-tool command preview receipts for Docker/Colima/Homebrew/package-manager cleanup
- Xcode DerivedData and developer cache review
- Homebrew, npm, pnpm, Yarn, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter cache rules
- Browser cache versus browser profile separation
- Stale temp/scratch review
- App-managed holding area for reversible quarantine moves
- Local audit history for plans and execution receipts

## Safety Model

Ryddi classifies findings into:

- `autoSafe` - rebuildable cache/temp data that can be selected after checks
- `safeAfterCondition` - likely safe, but requires a condition such as quitting an app or using a native cleanup tool
- `reviewRequired` - useful signal, no automatic action
- `preserveByDefault` - valuable data such as sessions, profiles, assets, archives, or app-managed state
- `neverTouch` - credentials, config, memories, app bundles, active state DBs, and other protected paths

Confirmed reclaim is blocked unless a clean dry-run receipt exists for the current plan. Direct delete is limited to allowlisted reproducible caches. Uncertain user-visible removals use Trash or the app-managed holding area.

## Build

```bash
swift build --scratch-path .build
swift test --scratch-path .build
```

Run the app or CLI from SwiftPM:

```bash
swift run --scratch-path .build RyddiApp
swift run --scratch-path .build reclaimer help
```

## CLI Quick Start

```bash
swift run --scratch-path .build reclaimer overview
swift run --scratch-path .build reclaimer status
swift run --scratch-path .build reclaimer overview --save-history --path Tests --limit 5
swift run --scratch-path .build reclaimer history list
swift run --scratch-path .build reclaimer history diff --group category
swift run --scratch-path .build reclaimer scan
swift run --scratch-path .build reclaimer scan --sort category --group category --limit 40
swift run --scratch-path .build reclaimer scan --review large --large-threshold 1000000000
swift run --scratch-path .build reclaimer duplicates --path ~/Downloads --min-size 10000000
swift run --scratch-path .build reclaimer apps --min-size 10000000
swift run --scratch-path .build reclaimer native --path ~/.colima --save-audit
swift run --scratch-path .build reclaimer containers --timeout 5 --save-audit
swift run --scratch-path .build reclaimer policy protect ~/Documents/Important --reason "never clean"
swift run --scratch-path .build reclaimer policy exclude ~/Downloads/NoisyScratch
swift run --scratch-path .build reclaimer plan --json
swift run --scratch-path .build reclaimer explain ~/.codex
swift run --scratch-path .build reclaimer execute --dry-run --path ~/Library/Caches/Codex
swift run --scratch-path .build reclaimer holding list
```

Execution is dry-run unless `--yes` is supplied. Even with `--yes`, the executor refuses protected classes, revalidates the path, reclassifies it, and skips open files.

## Protections And Exclusions

Ryddi stores local user path policy under Application Support:

```bash
swift run --scratch-path .build reclaimer policy list
swift run --scratch-path .build reclaimer policy protect ~/Projects/KeepMe --reason "active work"
swift run --scratch-path .build reclaimer policy exclude ~/Downloads/NoisyScratch --reason "ignore churn"
swift run --scratch-path .build reclaimer policy remove ~/Downloads/NoisyScratch --kind exclude
```

Protected paths stay visible but are forced to preserve-by-default/report-only and cannot be selected by cleanup plans. Excluded paths are skipped during scans and excluded from parent directory measurement. Use `--ignore-user-policy` only for debugging or fixture verification.

Holding-area expiry is also dry-run unless confirmed:

```bash
swift run --scratch-path .build reclaimer holding expire --older-than-days 30
swift run --scratch-path .build reclaimer holding expire --older-than-days 30 --yes
```

## App Bundle

```bash
Scripts/package-app.sh
```

This creates:

```text
dist/Ryddi.app
```

Set `CODESIGN_IDENTITY` to sign locally with Hardened Runtime. Use `Scripts/notarize-app.sh dist/Ryddi.app` when Apple notarization credentials are configured.

For a fuller release-shaped check:

```bash
Scripts/release-check.sh
```

This runs tests, builds `dist/Ryddi.app`, verifies bundled executables and rule resources, smoke-tests the packaged CLI, records signing state, creates `dist/Ryddi-developer-preview.zip`, writes a SHA-256 checksum, and emits `dist/Ryddi-release-manifest.txt`.

Unsigned preview artifacts are intentionally labeled as developer previews. They are not notarization receipts and may trigger Gatekeeper warnings. The manual **Release Preview Artifact** GitHub Actions workflow runs the same check and uploads the zip, checksum, and manifest as CI artifacts.

## Scheduler

```bash
swift run --scratch-path .build reclaimer schedule install
```

The LaunchAgent is report-first and runs:

```bash
reclaimer plan --json --save-audit
```

It does not run destructive cleanup unattended.

## Native Tool Reports

Ryddi treats container runtimes and package-manager stores as tool-owned state. For findings such as Docker, Colima, Homebrew, npm, pnpm, Yarn, SwiftPM, Cargo, Go, Gradle, Maven, and CocoaPods, use:

```bash
swift run --scratch-path .build reclaimer native --json --path ~/.colima
```

The report is a preview receipt: command, purpose, risk, expected effect, and non-claims. It can be saved with `--save-audit`, but Ryddi does not run these commands automatically and does not raw-delete VM disks, volumes, or package stores.

## Container Inventory

For Docker and Colima, Ryddi can also run read-only inspection commands:

```bash
swift run --scratch-path .build reclaimer containers --json --timeout 5 --save-audit
```

This records Docker storage buckets, images, containers, volumes, contexts, Colima profiles, command exit states, and missing/not-running tool states. It does not run prune, delete, stop, reset, or raw VM-disk commands.

## Repository Layout

```text
Sources/ReclaimerCore/       Shared scanner, rules, planner, executor, audit, holding, scheduler
Sources/reclaimer/           CLI
Sources/MacDiskReclaimerApp/ SwiftUI app target
Sources/ReclaimerAgent/      Scheduled report runner
Tests/ReclaimerCoreTests/    Safety and fixture tests
Scripts/                     Packaging and notarization helpers
```

## Product Research

- [Competitive research snapshot](docs/COMPETITIVE_RESEARCH.md) - competitor lanes, expected features, and suggested Ryddi roadmap.
- [Release checklist](docs/RELEASE_CHECKLIST.md) - developer preview versus signed/notarized release gates.

## Non-Goals For v1

- automatic duplicate cleanup, smart duplicate selection, or Photos/Music duplicate management
- app uninstall, automatic app-support cleanup, or smart leftover deletion
- malware scanning
- RAM cleaning or "optimizer" features
- root helper/system-wide cleanup
- automatic deletion of review-required items
- raw deletion of Docker/Colima VM disks or volumes
- automatic execution of Docker/Colima/Homebrew/package-manager prune/reset commands
- Mac App Store sandbox distribution

## GitHub About

Short description:

```text
Local-first macOS disk reclaim assistant for developer and AI-agent bloat.
```

Topics:

```text
macos swift swiftui disk-cleanup developer-tools codex docker colima xcode local-first privacy
```

## License

MIT.
