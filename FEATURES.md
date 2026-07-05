# Ryddi Feature Matrix

Ryddi is intentionally not a generic "clean my Mac" button. It is an evidence-first reclaim assistant for developer and AI-agent storage growth.

## Needed MVP Features And Chosen Solutions

| Feature | Best MVP solution | Implemented |
| --- | --- | --- |
| Find large offenders | Bounded filesystem scanner over known developer/agent roots, with explicit custom `--path` support. | `FileScanner`, `DefaultScopes`, `reclaimer scan` |
| Show top offenders | Shared overview analytics with category, safety, scope, age, logical size, allocated size, and top finding summaries. | `FindingAnalytics`, `reclaimer overview`, app Top Offenders |
| Explain scan coverage | Report missing/restricted/readable scopes, degraded scan behavior, and provide a direct Full Disk Access settings shortcut. | `ScanOverview`, app Permission Coverage |
| Explain APFS accounting | Surface logical versus allocated size and caveats around clones, sparse files, snapshots, and purgeable storage. | `storageAccountingNote`, `ScanOverview.accountingNotes` |
| Classify safety | Versioned data-driven rules, not hard-coded mystery heuristics. | `Resources/rules.json`, `RuleEngine` |
| Explain decisions | Every finding carries rule matches, evidence, recovery notes, and conditions. | `Finding`, `Evidence`, app detail view, `reclaimer explain` |
| Review large/old files | Size and age create review-only signals, never automatic cleanup permission. | dynamic scanner review signals |
| Inspect in native tools | Copy path, reveal in Finder, Quick Look, and open Terminal for reviewed findings. | app finding action buttons |
| Protect valuable data | Default preserve/never-touch for user documents, creative assets, credentials, browser profiles, VM/container state, and Codex history. | rule pack and executor protected-class checks |
| Handle active files | Check open handles before planning/execution and skip active paths. | `LsofOpenFileChecker`, `PlanBuilder`, `ReclaimerExecutor` |
| Avoid blind deletes | Build a dry-run plan first; UI exposes dry-run receipts and enables reclaim only after a clean dry run. | `ReclaimPlan`, `ExecutionReceipt`, app Dry Run/Reclaim |
| Reclaim safely | Use Trash for uncertain/user-visible data, direct delete only for allowlisted caches, compression only for cold files, holding area for reversible moves, with app confirmation before execution. | `ReclaimerExecutor`, app Reclaim confirmation |
| Restore held items | Store holding metadata so held items can be listed, restored, or expired after review. | `HoldingStore`, `reclaimer holding`, app Holding Area |
| Prefer native cleanup | Report Docker/Colima/package-manager cleanup as native-tool guidance rather than deleting stores directly. | rule pack `nativeToolCommand` findings |
| Automate conservatively | Scheduled job writes report plans only; unattended destructive cleanup is not enabled in v1. | `LaunchAgentManager`, `ReclaimerAgent`, `schedule install` |
| Keep local audit trail | Save plans and receipts under Application Support with local-only JSON. | `AuditStore`, app Audit History |
| Package for direct distribution | Build an unsigned `.app` bundle locally, with optional signing/notarization scripts for direct distribution. | `Scripts/package-app.sh`, `Scripts/notarize-app.sh` |
| Stay private | No telemetry, cloud upload, or remote AI analysis. | architecture and README policy |

## MVP Feature Boundaries

Included:

- Codex storage policy: caches/temp/logs versus sessions/state/credentials.
- Docker/Colima reporting and native cleanup guidance.
- Xcode and package-manager cache classification.
- SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter developer cache review.
- Browser cache versus browser profile distinction.
- Large-file and old-file review-only signals.
- Stale temp/scratch classification.
- App overview, top offenders, permission coverage, APFS notes, review queues, item detail, feature matrix, dry-run plan, audit history, and settings copy.

Deferred:

- Duplicate detection.
- Malware scanning.
- App updater.
- RAM/performance optimizer features.
- Root helper or system-wide cleanup.
- Mac App Store sandbox packaging.
- Automatic deletion of safe-after-condition or review-required items.
- Full Disk Access onboarding beyond coverage/degraded-mode copy.

## Acceptance Criteria

- `swift test --scratch-path .build` passes.
- `reclaimer plan --path ~/.codex --no-lsof` classifies Codex sessions as preserve/review, cache/temp as auto-safe, and credentials/state as never-touch.
- `reclaimer execute --dry-run` never mutates files.
- App Reclaim is disabled until a successful dry-run receipt exists for the current plan.
- `reclaimer holding restore` restores a held fixture, and `holding expire` is dry-run unless `--yes` is supplied.
- `Scripts/package-app.sh` produces `dist/Ryddi.app` with the bundled rule resources copied into the app bundle.
- The app can scan, build a dry-run plan, show feature coverage, show item evidence, and show local audit history.
- `reclaimer overview` reports top offenders, permission coverage, category summaries, and APFS notes.
- Large/old file signals remain review-only and are not selected by an auto-safe plan.
