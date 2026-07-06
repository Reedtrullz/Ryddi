# Ryddi

[![CI](https://github.com/Reedtrullz/Ryddi/actions/workflows/ci.yml/badge.svg)](https://github.com/Reedtrullz/Ryddi/actions/workflows/ci.yml)

Ryddi is a local-first macOS disk reclaim assistant for general Mac cleanup, with a developer and AI-agent cleanup pack being perfected first.

It is named from Norwegian **ryddig** / **rydde**: tidy, orderly, to clean up. The goal is not to be a scary one-click cleaner. Ryddi scans, explains, plans, and only then helps you reclaim space with receipts and guardrails.

## About

Modern Macs accumulate a strange mix of bloat: Downloads, old installers, caches, logs, large media, app-support leftovers, browser data, developer build products, Codex sessions and caches, Docker and Colima VM data, Xcode artifacts, and package-manager stores. Some of that is pure trash. Some of it is valuable history. Some of it is dangerous to touch directly.

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

- top-offender overview with category, owner/app/tool, safety, age, logical size, and allocated size
- scan presets for Developer, General Mac, and All roots, plus scope preview before scanning
- proportional visual map nodes by category, using non-overlapping allocated-size accounting
- hierarchical disk drill-down for scanned roots, with bounded child rows, safety/action/category hints, and explicit non-additive accounting notes
- ownership-aware storage summaries that group findings by app/tool hints such as Codex, Docker, Colima, Xcode, Homebrew, and Chrome
- local scan history snapshots and category growth deltas
- exportable local Markdown growth reports comparing saved scan snapshots
- menu bar disk-pressure status with report-only scan shortcut
- permission/degraded-scan coverage, first-run Full Disk Access walkthrough, and APFS accounting notes
- exportable local Markdown evidence reports with top findings, safety buckets, user policy, and non-claims
- exportable local Markdown reclaim plan reports with selected actions, blocked items, safety buckets, and non-claims
- exportable local Markdown receipt reports with before/after free-space notes, action counts, skipped/errors, and non-claims
- Recovery Center for app-held restores plus honest Trash, dry-run, skipped, native-tool, and non-recoverable receipt guidance
- report privacy controls for full, home-relative, or redacted paths plus user-entered reason redaction
- transparent bundled rule catalog showing safety classes, actions, categories, match hints, conditions, recovery notes, and non-claims
- active-handle review for cleanup candidates, with process summaries and failed-check visibility
- Finder, Quick Look, Terminal, and copy-path actions in the app
- local user protections and exclusions for paths Ryddi should preserve or ignore, with JSON import/export
- large-file and old-file review signals
- duplicate-file review with local content hashing, explicit CLI paths, and no automatic cleanup
- apps-and-leftovers review for installed app support files and heuristic orphan candidates
- AI-agent storage review for Codex, Claude, Cursor, Windsurf, and Ollama, separating reclaimable cache from valuable history and protected state
- Codex cache/temp/log/session policy
- Docker and Colima reporting with native-tool guidance
- read-only Docker/Colima inventory for storage buckets, images, containers, volumes, profiles, and command outcomes
- native-tool command preview receipts for Docker/Colima/Homebrew/package-manager cleanup
- Xcode DerivedData and developer cache review
- Homebrew, npm, pnpm, Yarn, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter cache rules
- Browser cache versus browser profile separation
- Stale temp/scratch review
- App-managed holding area for reversible quarantine moves
- Local audit history for plans, execution receipts, native reports, container reports, and active-file reports

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
swift run --scratch-path .build reclaimer drilldown --preset general --max-depth 3 --limit 8
swift run --scratch-path .build reclaimer scopes --preset general
swift run --scratch-path .build reclaimer overview --preset general
swift run --scratch-path .build reclaimer scan --preset all --review large
swift run --scratch-path .build reclaimer rules
swift run --scratch-path .build reclaimer status
swift run --scratch-path .build reclaimer permissions
swift run --scratch-path .build reclaimer permissions guide --output ryddi-permissions-guide.md
swift run --scratch-path .build reclaimer active --path ~/Library/Caches --limit 25
swift run --scratch-path .build reclaimer overview --save-history --path Tests --limit 5
swift run --scratch-path .build reclaimer report --path Tests --limit 10 --output ryddi-report.md
swift run --scratch-path .build reclaimer report --path Tests --path-style redacted --redact-user-text --output ryddi-report-redacted.md
swift run --scratch-path .build reclaimer history list
swift run --scratch-path .build reclaimer history diff --group category
swift run --scratch-path .build reclaimer history report --output ryddi-growth-report.md
swift run --scratch-path .build reclaimer scan
swift run --scratch-path .build reclaimer scan --sort category --group category --limit 40
swift run --scratch-path .build reclaimer scan --review large --large-threshold 1000000000
swift run --scratch-path .build reclaimer duplicates --path ~/Downloads --min-size 10000000
swift run --scratch-path .build reclaimer apps --min-size 10000000
swift run --scratch-path .build reclaimer agents
swift run --scratch-path .build reclaimer agents --json --limit 40
swift run --scratch-path .build reclaimer native --path ~/.colima --save-audit
swift run --scratch-path .build reclaimer containers --timeout 5 --save-audit
swift run --scratch-path .build reclaimer policy protect ~/Documents/Important --reason "never clean"
swift run --scratch-path .build reclaimer policy exclude ~/Downloads/NoisyScratch
swift run --scratch-path .build reclaimer policy export --output ryddi-policy.json
swift run --scratch-path .build reclaimer policy import ryddi-policy.json
swift run --scratch-path .build reclaimer plan --json
swift run --scratch-path .build reclaimer plan --path Tests --output ryddi-plan-report.md
swift run --scratch-path .build reclaimer plans export --path-style redacted --output ryddi-plan-report-redacted.md
swift run --scratch-path .build reclaimer explain ~/.codex
swift run --scratch-path .build reclaimer execute --dry-run --path ~/Library/Caches/Codex
swift run --scratch-path .build reclaimer receipts list
swift run --scratch-path .build reclaimer receipts export --output ryddi-receipt-report.md
swift run --scratch-path .build reclaimer receipts export --path-style redacted --output ryddi-receipt-report-redacted.md
swift run --scratch-path .build reclaimer recovery list
swift run --scratch-path .build reclaimer recovery restore HOLDING_ID --to ~/Restored-Ryddi-Item
swift run --scratch-path .build reclaimer holding list
```

Execution is dry-run unless `--yes` is supplied. Even with `--yes`, the executor refuses protected classes, revalidates the path, reclassifies it, and skips open files.

## Permission Coverage

Ryddi can summarize current scan coverage before you review cleanup candidates:

```bash
swift run --scratch-path .build reclaimer permissions
swift run --scratch-path .build reclaimer permissions --json --path ~/Library
swift run --scratch-path .build reclaimer permissions guide --output ryddi-permissions-guide.md
```

The permission advisor reports readable, denied, missing, and unknown scopes; recommends when to review Full Disk Access; and keeps explicit non-claims because path readability is not cleanup permission. The walkthrough adds first-run steps, a settings URL, rescan/report-only commands, affected scopes, and a local Markdown export. It does not grant macOS permissions or prove that Full Disk Access is enabled.

## Disk Drilldown

Ryddi can render a bounded hierarchy for scanned roots:

```bash
swift run --scratch-path .build reclaimer drilldown --preset general --max-depth 3 --limit 8
swift run --scratch-path .build reclaimer drilldown --path ~/Library/Caches --min-size 1000000 --tree-depth 4
```

The drill-down view is for navigation and evidence review. Parent rows include descendant bytes, so parent and child rows should not be added together as independent reclaim totals, and clicking through the app drill-down does not select cleanup.

## Active Handles

Ryddi can run a focused active-file review for cleanup-relevant candidates:

```bash
swift run --scratch-path .build reclaimer active --path ~/Library/Caches --limit 25
swift run --scratch-path .build reclaimer active --json --save-audit
```

The active review reports paths blocked by open handles or failed open-file checks, including process summaries when `lsof` can provide them. It does not quit apps, execute cleanup, or prove that a path becomes safe after an app exits.

## AI Agent Storage

Ryddi can run a focused review over common AI-agent roots:

```bash
swift run --scratch-path .build reclaimer agents
swift run --scratch-path .build reclaimer agents --json --limit 40
swift run --scratch-path .build reclaimer agents --path ~/.codex --path ~/.claude
```

The report groups Codex, Claude, Cursor, Windsurf, and Ollama storage into reclaimable cache, quit-first data, valuable history, protected state, and manual review. It is still report-only: agent sessions, memories, credentials, config, model state, and profiles are not deleted automatically, and cache cleanup still goes through the normal plan and dry-run gates.

## Protections And Exclusions

Ryddi stores local user path policy under Application Support:

```bash
swift run --scratch-path .build reclaimer policy list
swift run --scratch-path .build reclaimer policy protect ~/Projects/KeepMe --reason "active work"
swift run --scratch-path .build reclaimer policy exclude ~/Downloads/NoisyScratch --reason "ignore churn"
swift run --scratch-path .build reclaimer policy remove ~/Downloads/NoisyScratch --kind exclude
swift run --scratch-path .build reclaimer policy export --output ryddi-user-path-policy.json
swift run --scratch-path .build reclaimer policy import ryddi-user-path-policy.json
swift run --scratch-path .build reclaimer policy import ryddi-user-path-policy.json --replace
```

Protected paths stay visible but are forced to preserve-by-default/report-only and cannot be selected by cleanup plans. Excluded paths are skipped during scans and excluded from parent directory measurement. Use `--ignore-user-policy` only for debugging or fixture verification.

Policy import merges by default: matching `kind + path` rules from the import update existing local entries, while unrelated local rules remain. Use `--replace` only when you want the imported file to become the whole policy. Policy exports can contain private local paths and user-entered reasons; importing a policy changes only Ryddi's local protection/exclusion rules and does not delete files, grant macOS permissions, or prove that imported paths still exist.

## Evidence Reports

Ryddi can export a local Markdown report for review, sharing, or before/after notes:

```bash
swift run --scratch-path .build reclaimer report --path ~/Library/Caches --limit 25 --output ryddi-report.md
swift run --scratch-path .build reclaimer report --save-report
```

Reports include scan coverage, safety buckets, top categories, top findings, local protections/exclusions, APFS/accounting notes, disk-pressure notes, and explicit non-claims. They do not execute cleanup and may include local paths.

Use `--path-style home-relative` to hide the home directory prefix, `--path-style redacted` or `--redact-paths` to replace report paths with `<path redacted>`, and `--redact-user-text` to hide user-entered policy reasons. Redaction affects the exported report; saved local audit records may still contain the original paths.

Saved scan history can also be exported as a before/after growth report:

```bash
swift run --scratch-path .build reclaimer overview --save-history --path ~/Library/Caches --limit 25
swift run --scratch-path .build reclaimer history report --group category --output ryddi-growth-report.md
swift run --scratch-path .build reclaimer history report --path-style redacted --output ryddi-growth-report-redacted.md
```

Growth reports compare saved snapshots by category, scope, or safety class. They are evidence for review, not cleanup proof: scope changes, permissions, APFS snapshots, clones, hard links, and purgeable space can make exact free-space deltas differ.

Proposed reclaim plans can also be exported before dry run or execution:

```bash
swift run --scratch-path .build reclaimer plan --path ~/Library/Caches/Codex --output ryddi-plan-report.md
swift run --scratch-path .build reclaimer plan --path ~/Library/Caches/Codex --save-audit
swift run --scratch-path .build reclaimer plans export --path-style redacted --output ryddi-plan-report-redacted.md
```

Plan reports summarize selected actions, blocked or review-only items, safety buckets, conditions, estimates, and non-claims. They do not execute cleanup and are not a substitute for a dry-run receipt.

Saved execution receipts can also be exported:

```bash
swift run --scratch-path .build reclaimer execute --dry-run --path ~/Library/Caches/Codex --save-audit
swift run --scratch-path .build reclaimer receipts export --output ryddi-receipt-report.md
```

Receipt reports summarize saved dry-run or execution receipts. They include action status counts, before/after free-space fields when available, skipped/error actions, and non-claims. Exporting a receipt report does not rerun cleanup.

The Recovery Center combines app-held items and saved receipts:

```bash
swift run --scratch-path .build reclaimer recovery list
swift run --scratch-path .build reclaimer recovery --json
swift run --scratch-path .build reclaimer recovery restore HOLDING_ID
```

Ryddi can restore only items currently in its app-managed holding area. Trash actions require Finder Trash review, dry-run/skipped/error actions should not need recovery, and direct deletes or native-tool cleanup may require rebuilding caches, using the owning tool, or restoring from backup.

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
Sources/ReclaimerCore/       Shared scanner, rules, planner, executor, audit, recovery, holding, scheduler
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
Local-first macOS disk reclaim assistant for general cleanup with developer-first rules.
```

Topics:

```text
macos swift swiftui disk-cleanup mac-cleaner developer-tools codex docker colima xcode local-first privacy
```

## License

MIT.
