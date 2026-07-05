# Ryddi

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

## What It Handles

- Codex cache/temp/log/session policy
- Docker and Colima reporting with native-tool guidance
- Xcode DerivedData and developer cache review
- Homebrew, npm, pnpm, Yarn, Cargo, Go, Gradle, Maven, and CocoaPods cache rules
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
swift run --scratch-path .build reclaimer scan
swift run --scratch-path .build reclaimer plan --json
swift run --scratch-path .build reclaimer explain ~/.codex
swift run --scratch-path .build reclaimer execute --dry-run --path ~/Library/Caches/Codex
swift run --scratch-path .build reclaimer holding list
```

Execution is dry-run unless `--yes` is supplied. Even with `--yes`, the executor refuses protected classes, revalidates the path, reclassifies it, and skips open files.

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

## Scheduler

```bash
swift run --scratch-path .build reclaimer schedule install
```

The LaunchAgent is report-first and runs:

```bash
reclaimer plan --json --save-audit
```

It does not run destructive cleanup unattended.

## Repository Layout

```text
Sources/ReclaimerCore/       Shared scanner, rules, planner, executor, audit, holding, scheduler
Sources/reclaimer/           CLI
Sources/MacDiskReclaimerApp/ SwiftUI app target
Sources/ReclaimerAgent/      Scheduled report runner
Tests/ReclaimerCoreTests/    Safety and fixture tests
Scripts/                     Packaging and notarization helpers
```

## Non-Goals For v1

- duplicate-file detection
- malware scanning
- RAM cleaning or "optimizer" features
- root helper/system-wide cleanup
- automatic deletion of review-required items
- raw deletion of Docker/Colima VM disks or volumes
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
