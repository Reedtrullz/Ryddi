# Ryddi Feature Matrix

Ryddi is intentionally not a generic "clean my Mac" button. It is an evidence-first reclaim assistant for developer and AI-agent storage growth.

## Needed MVP Features And Chosen Solutions

| Feature | Best MVP solution | Implemented |
| --- | --- | --- |
| Find large offenders | Bounded filesystem scanner over known developer/agent roots, with explicit custom `--path` support. | `FileScanner`, `DefaultScopes`, `reclaimer scan` |
| Show top offenders | Shared overview analytics with category, safety, scope, age, logical size, allocated size, and top finding summaries. | `FindingAnalytics`, `reclaimer overview`, app Top Offenders |
| Visualize space | Proportional category map from non-overlapping allocated-size findings; informational only, not a cleanup selector. | `DiskMapNode`, app Visual Map, `overview` map nodes |
| Track growth | Local scan snapshots compare category/scope/safety growth between the latest two scans. | `ScanHistoryStore`, `reclaimer history`, app Growth History |
| Watch disk pressure | Menu bar status item and CLI status report current free space using explicit warning/critical thresholds. | `DiskStatusReader`, `reclaimer status`, app menu bar |
| Explain scan coverage | Report missing/restricted/readable scopes, degraded scan behavior, Full Disk Access guidance, and explicit permission non-claims. | `PermissionAdvisor`, `reclaimer permissions`, app Permissions |
| Explain APFS accounting | Surface logical versus allocated size and caveats around clones, sparse files, snapshots, and purgeable storage. | `storageAccountingNote`, `ScanOverview.accountingNotes` |
| Export evidence reports | Produce local Markdown reports with disk status, scan coverage, safety/category buckets, top findings, user policy, accounting notes, optional path privacy controls, and explicit non-claims. | `EvidenceReportBuilder`, `ReportPrivacyOptions`, `ReportStore`, `reclaimer report`, app Export Report |
| Classify safety | Versioned data-driven rules, not hard-coded mystery heuristics. | `Resources/rules.json`, `RuleEngine` |
| Explain decisions | Every finding carries rule matches, evidence, recovery notes, and conditions. | `Finding`, `Evidence`, app detail view, `reclaimer explain` |
| Honor user path policy | User protections keep paths visible but blocked from cleanup; user exclusions hide noisy paths from scans and parent measurements. | `UserPathPolicyStore`, `reclaimer policy`, app Protections & Exclusions |
| Review large/old files | Size and age create review-only signals, never automatic cleanup permission. | dynamic scanner review signals |
| Review duplicates | Size-bucketed local content hashing groups identical regular files as manual review signals; no delete action or plan item is emitted. | `DuplicateReviewScanner`, `reclaimer duplicates`, app Duplicate Review |
| Review apps & leftovers | Parse installed `.app` bundles and related Library files, then surface support data and orphan candidates as review-only guidance. | `AppReviewScanner`, `reclaimer apps`, app Apps & Leftovers |
| Inspect in native tools | Copy path, reveal in Finder, Quick Look, and open Terminal for reviewed findings. | app finding action buttons |
| Protect valuable data | Default preserve/never-touch for user documents, creative assets, credentials, browser profiles, VM/container state, and Codex history. | rule pack and executor protected-class checks |
| Handle active files | Check open handles before planning/execution, surface process names in an active-handle review, and skip active paths. | `LsofOpenFileChecker`, `ActiveFileReviewScanner`, `PlanBuilder`, `ReclaimerExecutor`, `reclaimer active`, app Active Handles |
| Avoid blind deletes | Build a dry-run plan first; UI exposes dry-run receipts and enables reclaim only after a clean dry run. | `ReclaimPlan`, `ExecutionReceipt`, app Dry Run/Reclaim |
| Export receipts | Convert saved dry-run/execution receipts into local Markdown with action counts, before/after free-space fields, skipped/errors, optional path privacy controls, and non-claims. | `ExecutionReceiptReportBuilder`, `ReportPrivacyOptions`, `reclaimer receipts export`, app Audit History export |
| Reclaim safely | Use Trash for uncertain/user-visible data, direct delete only for allowlisted caches, compression only for cold files, holding area for reversible moves, with app confirmation before execution. | `ReclaimerExecutor`, app Reclaim confirmation |
| Restore held items | Store holding metadata so held items can be listed, restored, or expired after review. | `HoldingStore`, `reclaimer holding`, app Holding Area |
| Prefer native cleanup | Report Docker/Colima/package-manager cleanup as preview-only native-tool receipts with command, purpose, risk, expected effect, audit save support, and explicit non-claims rather than deleting stores directly. | `NativeToolGuidance`, `reclaimer native`, app native receipt preview |
| Inventory containers | Run bounded read-only Docker/Colima inspection commands and record storage buckets, images, containers, volumes, profiles, missing/not-running states, and command outcomes. | `ContainerInventoryScanner`, `reclaimer containers`, app Container Inventory |
| Automate conservatively | Scheduled job writes report plans only; unattended destructive cleanup is not enabled in v1. | `LaunchAgentManager`, `ReclaimerAgent`, `schedule install` |
| Keep local audit trail | Save plans, receipts, native reports, container reports, and active-file reports under Application Support with local-only JSON. | `AuditStore`, app Audit History |
| Package for direct distribution | Build an unsigned developer preview or signed app bundle, verify release-shaped artifacts, create checksum/manifest output, and leave notarization as an explicit credentialed step. | `Scripts/package-app.sh`, `Scripts/release-check.sh`, `Scripts/notarize-app.sh`, release-preview workflow |
| Stay private | No telemetry, cloud upload, or remote AI analysis. | architecture and README policy |

## MVP Feature Boundaries

Included:

- Codex storage policy: caches/temp/logs versus sessions/state/credentials.
- Docker/Colima reporting and native cleanup guidance.
- Native-tool preview receipts for Docker/Colima/Homebrew/package-manager cleanup, with no automatic command execution.
- Read-only Docker/Colima live inventory for native storage estimates and profile/object context.
- Local user protections and exclusions.
- Xcode and package-manager cache classification.
- SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter developer cache review.
- Proportional visual map by category.
- Local scan history and growth deltas.
- Menu bar disk-pressure status with report-only scan shortcut.
- Exportable local Markdown evidence reports.
- Exportable local Markdown execution receipt reports.
- Report path privacy controls: full, home-relative, redacted, plus user-entered reason redaction.
- Active-handle review with process summaries for cleanup-relevant candidates.
- Permission advisor for readable/denied/missing scope coverage and Full Disk Access guidance.
- Browser cache versus browser profile distinction.
- Large-file and old-file review-only signals.
- Duplicate-file review for explicit CLI paths and bounded app scans, with preserve-by-default files excluded unless requested.
- Apps & Leftovers review for installed app support files and heuristic orphan candidates.
- Stale temp/scratch classification.
- App overview, top offenders, permission coverage, APFS notes, review queues, item detail, feature matrix, dry-run plan, audit history, and settings copy.

Deferred:

- Automatic duplicate cleanup, smart duplicate selection, similar-file matching, and Photos/Music duplicate management.
- App uninstall, automatic app-support cleanup, and smart leftover deletion.
- Malware scanning.
- App updater.
- RAM/performance optimizer features.
- Root helper or system-wide cleanup.
- Mac App Store sandbox packaging.
- Automatic deletion of safe-after-condition or review-required items.
- Automatic execution of native Docker/Colima/Homebrew/package-manager cleanup commands.
- Full Disk Access onboarding beyond the current advisor, settings shortcut, and degraded-mode labels.

## Acceptance Criteria

- `swift test --scratch-path .build` passes.
- `reclaimer plan --path ~/.codex --no-lsof` classifies Codex sessions as preserve/review, cache/temp as auto-safe, and credentials/state as never-touch.
- `reclaimer execute --dry-run` never mutates files.
- App Reclaim is disabled until a successful dry-run receipt exists for the current plan.
- `reclaimer holding restore` restores a held fixture, and `holding expire` is dry-run unless `--yes` is supplied.
- `Scripts/package-app.sh` produces `dist/Ryddi.app` with the bundled rule resources copied into the app bundle.
- `Scripts/release-check.sh` runs tests, builds `dist/Ryddi.app`, validates bundle layout/resources, smoke-tests the packaged CLI, records signing state, and creates a zip/checksum/manifest.
- The app can scan, build a dry-run plan, show feature coverage, show item evidence, and show local audit history.
- `reclaimer overview` reports top offenders, permission coverage, category summaries, and APFS notes.
- `reclaimer permissions --json --path FIXTURE` reports coverage level, readable/denied/missing counts, recommended actions, and non-claims.
- `reclaimer active --path FIXTURE --json` reports cleanup candidates blocked by open handles or failed open-file checks, with process summaries when available, and does not quit processes or execute cleanup.
- `reclaimer report --path FIXTURE --limit 5 --output REPORT.md` writes a local Markdown report with top findings, policy, accounting notes, and non-claims without executing cleanup.
- `reclaimer report --path FIXTURE --path-style redacted --redact-user-text --output REPORT.md` writes a share-safer Markdown report without full local paths or user-entered policy reasons.
- `reclaimer receipts export --output RECEIPT.md` writes a local Markdown report for a saved receipt without rerunning cleanup.
- `reclaimer receipts export --path-style redacted --output RECEIPT.md` redacts receipt action paths and path-bearing messages without mutating the saved receipt.
- `reclaimer status --json` reports disk pressure and free-space notes without scanning content.
- `reclaimer history record/list/diff` stores local scan snapshots and reports category/scope/safety deltas.
- `reclaimer duplicates --path FIXTURE --min-size 1` groups same-content regular files, skips protected paths, and emits review-only `openGuidance` candidates.
- `reclaimer apps --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1` reports installed app support files and orphan candidates without creating plan items.
- `reclaimer native --path FIXTURE --json` emits preview-only native-tool receipts for matching Docker/Colima/package-manager findings and can save them to local audit history.
- `reclaimer containers --json --timeout 2` emits a read-only Docker/Colima inventory, classifies missing versus not-running tools, and never emits prune/delete/stop/reset commands.
- `reclaimer policy protect/exclude/list/remove` writes local-only path policy, protects configured paths from cleanup selection, and excludes configured paths from scan output.
- Visual map accounting does not double-count nested directory findings.
- Large/old file signals remain review-only and are not selected by an auto-safe plan.
- Duplicate review findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
- Apps & Leftovers findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
