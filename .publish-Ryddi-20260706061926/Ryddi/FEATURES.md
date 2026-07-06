# Ryddi Feature Matrix

Ryddi is intentionally not a scary one-click "clean my Mac" button. It is an evidence-first general Mac reclaim assistant, with developer and AI-agent storage cleanup as the first deep rule pack.

## Needed MVP Features And Chosen Solutions

| Feature | Best MVP solution | Implemented |
| --- | --- | --- |
| Choose scan scope | Named presets for Developer, General Mac, and All roots, plus explicit custom `--path` support and scope preview. | `ScanScopePreset`, `ScanScopePlan`, `DefaultScopes`, `reclaimer scopes`, app Scan Scope |
| Find large offenders | Bounded filesystem scanner over preset or custom roots, with permission evidence. | `FileScanner`, `DefaultScopes`, `reclaimer scan` |
| Show top offenders | Shared overview analytics with category, owner/app/tool, safety, scope, age, logical size, allocated size, and top finding summaries. | `FindingAnalytics`, `reclaimer overview`, app Top Offenders |
| Visualize space | Proportional category map from non-overlapping allocated-size findings; informational only, not a cleanup selector. | `DiskMapNode`, app Visual Map, `overview` map nodes |
| Explain ownership | Group non-overlapping findings by scanner owner hints or category fallback so users can see which app/tool appears responsible for storage. | `OwnerStorageSummary`, `ScanOverview.ownerSummaries`, `reclaimer overview`, app Top Owners, evidence reports |
| Track growth | Local scan snapshots compare category/scope/safety growth between scans and export local before/after Markdown reports. | `ScanHistoryStore`, `GrowthReportBuilder`, `reclaimer history`, `reclaimer history report`, app Growth History |
| Watch disk pressure | Menu bar status item and CLI status report current free space using explicit warning/critical thresholds. | `DiskStatusReader`, `reclaimer status`, app menu bar |
| Explain scan coverage | Report missing/restricted/readable scopes, degraded scan behavior, first-run Full Disk Access walkthrough steps, exportable guidance, and explicit permission non-claims. | `PermissionAdvisor`, `PermissionWalkthroughBuilder`, `reclaimer permissions`, `reclaimer permissions guide`, app Permissions |
| Explain APFS accounting | Surface logical versus allocated size and caveats around clones, sparse files, snapshots, and purgeable storage. | `storageAccountingNote`, `ScanOverview.accountingNotes` |
| Export evidence reports | Produce local Markdown reports with disk status, scan coverage, safety/category buckets, top findings, user policy, accounting notes, optional path privacy controls, and explicit non-claims. | `EvidenceReportBuilder`, `ReportPrivacyOptions`, `ReportStore`, `reclaimer report`, app Export Report |
| Export plan reports | Produce local Markdown reports for proposed reclaim plans with selected actions, blocked/review items, safety buckets, estimates, optional path privacy controls, and explicit non-claims. | `ReclaimPlanReportBuilder`, `ReportPrivacyOptions`, `reclaimer plan --output`, `reclaimer plans export`, app plan export |
| Classify safety | Versioned data-driven rules, not hard-coded mystery heuristics. | `Resources/rules.json`, `RuleEngine` |
| Inspect bundled rules | Read-only rule catalog exposes rule version, safety/action/category summaries, match hints, conditions, recovery notes, and non-claims. | `RuleCatalogReport`, `reclaimer rules`, app Rule Catalog |
| Explain decisions | Every finding carries rule matches, evidence, recovery notes, and conditions. | `Finding`, `Evidence`, app detail view, `reclaimer explain` |
| Honor user path policy | User protections keep paths visible but blocked from cleanup; user exclusions hide noisy paths from scans and parent measurements; JSON import/export lets users carry policy between Macs or attach redacted rule context to reviews. | `UserPathPolicyStore`, `UserPathPolicyDocument`, `reclaimer policy`, app Protections & Exclusions |
| Review large/old files | Size and age create review-only signals, never automatic cleanup permission. | dynamic scanner review signals |
| Review duplicates | Size-bucketed local content hashing groups identical regular files as manual review signals; no delete action or plan item is emitted. | `DuplicateReviewScanner`, `reclaimer duplicates`, app Duplicate Review |
| Review apps & leftovers | Parse installed `.app` bundles and related Library files, then surface support data and orphan candidates as review-only guidance. | `AppReviewScanner`, `reclaimer apps`, app Apps & Leftovers |
| Review AI-agent storage | Scan common Codex, Claude, Cursor, Windsurf, and Ollama roots, then bucket cache/log churn separately from valuable history, protected state, and manual review. | `AgentStorageReviewBuilder`, `DefaultScopes.aiAgentStorage`, `reclaimer agents`, app AI Agent Storage |
| Inspect in native tools | Copy path, reveal in Finder, Quick Look, and open Terminal for reviewed findings. | app finding action buttons |
| Protect valuable data | Default preserve/never-touch for user documents, creative assets, credentials, browser profiles, VM/container state, and Codex history. | rule pack and executor protected-class checks |
| Handle active files | Check open handles before planning/execution, surface process names in an active-handle review, and skip active paths. | `LsofOpenFileChecker`, `ActiveFileReviewScanner`, `PlanBuilder`, `ReclaimerExecutor`, `reclaimer active`, app Active Handles |
| Avoid blind deletes | Build a dry-run plan first; UI exposes dry-run receipts and enables reclaim only after a clean dry run. | `ReclaimPlan`, `ExecutionReceipt`, app Dry Run/Reclaim |
| Export receipts | Convert saved dry-run/execution receipts into local Markdown with action counts, before/after free-space fields, skipped/errors, optional path privacy controls, and non-claims. | `ExecutionReceiptReportBuilder`, `ReportPrivacyOptions`, `reclaimer receipts export`, app Audit History export |
| Reclaim safely | Use Trash for uncertain/user-visible data, direct delete only for allowlisted caches, compression only for cold files, holding area for reversible moves, with app confirmation before execution. | `ReclaimerExecutor`, app Reclaim confirmation |
| Restore held items | Store holding metadata so held items can be listed, restored, or expired after review. | `HoldingStore`, `reclaimer holding`, app Holding Area |
| Review recovery | Combine app-held items and saved receipts into a recovery view that separates Ryddi-restorable items from Trash review, dry-run/skipped no-ops, native-tool guidance, and non-recoverable direct deletes. | `RecoveryCenter`, `reclaimer recovery`, app Recovery Center |
| Prefer native cleanup | Report Docker/Colima/package-manager cleanup as preview-only native-tool receipts with command, purpose, risk, expected effect, audit save support, and explicit non-claims rather than deleting stores directly. | `NativeToolGuidance`, `reclaimer native`, app native receipt preview |
| Inventory containers | Run bounded read-only Docker/Colima inspection commands and record storage buckets, images, containers, volumes, profiles, missing/not-running states, and command outcomes. | `ContainerInventoryScanner`, `reclaimer containers`, app Container Inventory |
| Automate conservatively | Scheduled job writes report plans only; unattended destructive cleanup is not enabled in v1. | `LaunchAgentManager`, `ReclaimerAgent`, `schedule install` |
| Keep local audit trail | Save plans, receipts, native reports, container reports, and active-file reports under Application Support with local-only JSON. | `AuditStore`, app Audit History |
| Package for direct distribution | Build an unsigned developer preview or signed app bundle, verify release-shaped artifacts, create checksum/manifest output, and leave notarization as an explicit credentialed step. | `Scripts/package-app.sh`, `Scripts/release-check.sh`, `Scripts/notarize-app.sh`, release-preview workflow |
| Stay private | No telemetry, cloud upload, or remote AI analysis. | architecture and README policy |

## MVP Feature Boundaries

Included:

- General Mac scan preset for Downloads, Desktop, personal folder review, user caches/logs, app support, attachments, device backups, and Trash review.
- Codex storage policy: caches/temp/logs versus sessions/state/credentials.
- Docker/Colima reporting and native cleanup guidance.
- Native-tool preview receipts for Docker/Colima/Homebrew/package-manager cleanup, with no automatic command execution.
- Read-only Docker/Colima live inventory for native storage estimates and profile/object context.
- Local user protections and exclusions, plus user path policy JSON import/export.
- Xcode and package-manager cache classification.
- SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter developer cache review.
- Proportional visual map by category.
- Local scan history and growth deltas.
- Exportable local Markdown growth reports for saved snapshot comparisons.
- Menu bar disk-pressure status with report-only scan shortcut.
- Exportable local Markdown evidence reports.
- Exportable local Markdown reclaim plan reports.
- Exportable local Markdown execution receipt reports.
- Recovery Center for app-held restores and receipt-based recovery guidance.
- Report path privacy controls: full, home-relative, redacted, plus user-entered reason redaction.
- Active-handle review with process summaries for cleanup-relevant candidates.
- Permission advisor and first-run walkthrough for readable/denied/missing scope coverage, Full Disk Access guidance, degraded-mode labels, rescan commands, and permission non-claims.
- Browser cache versus browser profile distinction.
- Large-file and old-file review-only signals.
- Duplicate-file review for explicit CLI paths and bounded app scans, with preserve-by-default files excluded unless requested.
- Apps & Leftovers review for installed app support files and heuristic orphan candidates.
- AI-agent storage review for Codex, Claude, Cursor, Windsurf, and Ollama, with cache/history/protected-state buckets and no automatic session/config/model cleanup.
- Stale temp/scratch classification.
- App overview, top offenders, owner summaries, rule catalog, permission coverage, APFS notes, review queues, item detail, feature matrix, dry-run plan, audit history, and settings copy.

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
- Screenshot/GIF walkthrough for Full Disk Access onboarding in release materials.

## Acceptance Criteria

- `swift test --scratch-path .build` passes.
- `reclaimer plan --path ~/.codex --no-lsof` classifies Codex sessions as preserve/review, cache/temp as auto-safe, and credentials/state as never-touch.
- `reclaimer execute --dry-run` never mutates files.
- App Reclaim is disabled until a successful dry-run receipt exists for the current plan.
- `reclaimer holding restore` restores a held fixture, and `holding expire` is dry-run unless `--yes` is supplied.
- `Scripts/package-app.sh` produces `dist/Ryddi.app` with the bundled rule resources copied into the app bundle.
- `Scripts/release-check.sh` runs tests, builds `dist/Ryddi.app`, validates bundle layout/resources, smoke-tests the packaged CLI, records signing state, and creates a zip/checksum/manifest.
- The app can scan, build a dry-run plan, show feature coverage, show item evidence, and show local audit history.
- `reclaimer overview` reports top offenders, permission coverage, category summaries, owner summaries, and APFS notes.
- `reclaimer rules --json` reports the bundled rule version, safety/action/category summaries, rule sections, match hints, conditions, recovery notes, and non-claims without scanning or executing cleanup.
- `reclaimer permissions --json --path FIXTURE` reports coverage level, readable/denied/missing counts, recommended actions, and non-claims.
- `reclaimer permissions guide --path FIXTURE --output GUIDE.md` writes a local Markdown first-run walkthrough with Full Disk Access steps, rescan/report-only commands, affected scopes, and non-claims.
- `reclaimer active --path FIXTURE --json` reports cleanup candidates blocked by open handles or failed open-file checks, with process summaries when available, and does not quit processes or execute cleanup.
- `reclaimer report --path FIXTURE --limit 5 --output REPORT.md` writes a local Markdown report with top findings, policy, accounting notes, and non-claims without executing cleanup.
- `reclaimer report --path FIXTURE --path-style redacted --redact-user-text --output REPORT.md` writes a share-safer Markdown report without full local paths or user-entered policy reasons.
- `reclaimer plan --path FIXTURE --output PLAN.md` writes a local Markdown reclaim plan report with selected actions, blocked/review items, safety buckets, estimates, and non-claims without executing cleanup.
- `reclaimer plans export --path-style redacted --output PLAN.md` exports a saved plan report with redacted action/review paths without mutating the saved plan.
- `reclaimer receipts export --output RECEIPT.md` writes a local Markdown report for a saved receipt without rerunning cleanup.
- `reclaimer receipts export --path-style redacted --output RECEIPT.md` redacts receipt action paths and path-bearing messages without mutating the saved receipt.
- `reclaimer recovery --json` reports app-held items as restorable, dry-run/skipped actions as no-op evidence, Trash actions as Finder Trash review, and direct deletes/native-tool actions as non-Ryddi recovery guidance.
- `reclaimer recovery restore HOLDING_ID --to DESTINATION` restores a disposable held fixture and refuses to treat receipt-only rows as Ryddi-restorable.
- `reclaimer status --json` reports disk pressure and free-space notes without scanning content.
- `reclaimer history record/list/diff` stores local scan snapshots and reports category/scope/safety deltas.
- `reclaimer history report --output GROWTH.md` writes a local Markdown before/after report for saved scan snapshots, with category/scope/safety grouping, path privacy controls, and non-claims.
- `reclaimer duplicates --path FIXTURE --min-size 1` groups same-content regular files, skips protected paths, and emits review-only `openGuidance` candidates.
- `reclaimer apps --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1` reports installed app support files and orphan candidates without creating plan items.
- `reclaimer agents --path FIXTURE --min-size 1 --max-depth 4 --json` reports AI-agent storage buckets, including reclaimable cache, valuable history, protected state, and quit-first data without creating plan items.
- `reclaimer native --path FIXTURE --json` emits preview-only native-tool receipts for matching Docker/Colima/package-manager findings and can save them to local audit history.
- `reclaimer containers --json --timeout 2` emits a read-only Docker/Colima inventory, classifies missing versus not-running tools, and never emits prune/delete/stop/reset commands.
- `reclaimer policy protect/exclude/list/remove/export/import` writes local-only path policy, protects configured paths from cleanup selection, excludes configured paths from scan output, exports a versioned JSON document, imports by merge by default, and supports explicit `--replace`.
- Visual map accounting does not double-count nested directory findings.
- Owner summaries do not double-count nested directory findings and prefer explicit owner hints over category fallback.
- Large/old file signals remain review-only and are not selected by an auto-safe plan.
- Duplicate review findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
- Apps & Leftovers findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
