# Ryddi Feature Matrix

Ryddi is intentionally not a scary one-click "clean my Mac" button. It is an evidence-first general Mac reclaim assistant, with developer and AI-agent storage cleanup as the first deep rule pack.

## Needed MVP Features And Chosen Solutions

| Feature | Best MVP solution | Implemented |
| --- | --- | --- |
| Choose scan scope | Named presets for Developer, General Mac, and All roots, built-in guided templates, explicit custom `--path` support, saved scope sets, and scope preview. | `ScanScopePreset`, `ScopeTemplateCatalog`, `ScanScopePlan`, `SavedScopeSetStore`, `DefaultScopes`, `reclaimer scopes`, app Scan Scope, app Scope Sets |
| Find large offenders | Bounded filesystem scanner over preset or custom roots, with permission evidence. | `FileScanner`, `DefaultScopes`, `reclaimer scan` |
| Show top offenders | Shared overview analytics with sortable/groupable rows by category, owner/app/tool, safety, scope, age, action, logical size, allocated size, confidence, and conservative reclaim estimate. | `TopOffenderTable`, `FindingAnalytics`, `reclaimer overview --sort --group`, app Top Offenders |
| Organize review queues | Shared user-intent queues separate safe maintenance, quit-first data, native-tool stores, valuable history, protected personal/app assets, and unknown review items, with single-queue filtering and evidence-detail navigation. | `ReviewQueueReport`, `ReviewQueueDetailReport`, `FindingAnalytics.reviewQueueReport`, `reclaimer queues --queue`, app Review Queues |
| Visualize space | Proportional category map plus bounded hierarchical drill-down from scan findings; informational only, not a cleanup selector. | `DiskMapNode`, `DiskDrillDownReport`, `reclaimer drilldown`, app Visual Map and Disk Drilldown |
| Explain ownership | Group non-overlapping findings by scanner owner hints or category fallback so users can see which app/tool appears responsible for storage. | `OwnerStorageSummary`, `ScanOverview.ownerSummaries`, `reclaimer overview`, app Top Owners, evidence reports |
| Track growth | Local scan snapshots compare category/scope/safety growth between scans and export local before/after Markdown reports. | `ScanHistoryStore`, `GrowthReportBuilder`, `reclaimer history`, `reclaimer history report`, app Growth History |
| Watch disk pressure | Menu bar status item and CLI status report current free space using explicit warning/critical thresholds. | `DiskStatusReader`, `reclaimer status`, app menu bar |
| Explain scan coverage | Report missing/restricted/readable scopes, degraded scan behavior, first-run Full Disk Access walkthrough steps, exportable guidance, and explicit permission non-claims. | `PermissionAdvisor`, `PermissionWalkthroughBuilder`, `reclaimer permissions`, `reclaimer permissions guide`, app Permissions |
| Explain APFS accounting | Surface logical versus allocated size and caveats around clones, sparse files, snapshots, and purgeable storage. | `storageAccountingNote`, `ScanOverview.accountingNotes` |
| Export evidence reports | Produce local Markdown reports with disk status, scan coverage, safety/category buckets, top findings, user policy, accounting notes, optional path privacy controls, and explicit non-claims. | `EvidenceReportBuilder`, `ReportPrivacyOptions`, `ReportStore`, `reclaimer report`, app Export Report |
| Export plan reports | Produce local Markdown reports for proposed reclaim plans with selected actions, blocked/review items, safety buckets, estimates, optional path privacy controls, and explicit non-claims. | `ReclaimPlanReportBuilder`, `ReportPrivacyOptions`, `reclaimer plan --output`, `reclaimer plans export`, app plan export |
| Classify safety | Versioned data-driven rules, not hard-coded mystery heuristics. | `Resources/rules.json`, `RuleEngine` |
| Inspect rules | Read-only rule catalog exposes rule version, bundled/user source, safety/action/category summaries, match hints, conditions, recovery notes, and non-claims. | `RuleCatalogReport`, `reclaimer rules`, app Rule Catalog |
| Explain decisions | Every finding can be rendered as a structured explanation covering what it is, why it matched, risk, cleanup permission, exact action semantics, removal effect, recovery path, conditions, next steps, and non-claims. | `FindingExplanationReport`, `FindingExplanationBuilder`, app detail view, `reclaimer explain` |
| Honor user path policy | User protections keep paths visible but blocked from cleanup; user exclusions hide noisy paths from scans and parent measurements; JSON import/export lets users carry policy between Macs or attach redacted rule context to reviews. | `UserPathPolicyStore`, `UserPathPolicyDocument`, `reclaimer policy`, app Protections & Exclusions |
| Review user rule packs | Local user rule packs can be previewed, validated, imported, exported, and included explicitly in scans; imported rules can only add review, preserve, or never-touch signals and cannot grant cleanup actions. | `UserRulePackStore`, `UserRulePackDocument`, `reclaimer rules user`, `--include-user-rules`, app Rule Catalog preview/import/export, app User Rules scan toggle |
| Review large/old files | Size and age create review-only signals, with a dedicated review mode that prefers concrete child files and never grants automatic cleanup permission. | `LargeOldReviewReport`, `FindingAnalytics.largeOldReviewReport`, `reclaimer large`, app Large & Old Files |
| Review archive candidates | Convert large/old review rows into a local checklist with keep, archive, Trash-review, cleanup-plan, manual-review, and blocked recommendations, without moving or compressing files. | `ArchiveReviewReport`, `ArchiveReviewBuilder`, `reclaimer archive`, app Archive Candidates panel |
| Review duplicates | Size-bucketed local content hashing groups identical regular files as manual review signals; no delete action or plan item is emitted. | `DuplicateReviewScanner`, `reclaimer duplicates`, app Duplicate Review |
| Review Downloads | Report old downloads, installers, archives, app bundles, kind summaries, largest items, Finder guidance, and local audit history without moving or deleting files. | `DownloadsReviewScanner`, `DownloadsReviewReport`, `reclaimer downloads`, app Downloads Review |
| Review browser caches | Report browser cache roots, browser/cache-kind summaries, largest cache items, protected profile roots, and quit-first guidance without modifying cache or profile state. | `BrowserCacheReviewScanner`, `BrowserCacheReviewReport`, `reclaimer browsers`, app Browser Cache Review |
| Review package caches | Report Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, and Playwright cache roots, package-manager/cache-kind summaries, largest cache items, protected config/auth paths, and native cleanup guidance without modifying package-manager state. | `PackageCacheReviewScanner`, `PackageCacheReviewReport`, `reclaimer packages`, app Package Cache Review |
| Review project dependencies | Report project-local dependency and build artifact folders such as node_modules, Python virtual environments, Swift .build, Rust target, Pods, .dart_tool, framework caches, Gradle, Flutter, and Android outputs while protecting source, manifests, lockfiles, env files, credentials, IDE settings, and unknown project state. Optional local VCS status and command hints add review context without executing cleanup. | `ProjectDependencyReviewScanner`, `ProjectDependencyReviewReport`, `reclaimer projects`, app Project Dependencies |
| Review Xcode storage | Report DerivedData, module/documentation caches, Products, Archives, DeviceSupport, simulator devices, runtimes, logs, preview simulator data, protected Xcode developer-state roots, and Xcode/simctl guidance without modifying Xcode state. | `XcodeReviewScanner`, `XcodeReviewReport`, `reclaimer xcode`, app Xcode Review |
| Review device backups | Report local iPhone/iPad MobileSync backup roots, size, age, encryption state, parsed metadata, missing metadata, Apple/Finder guidance, and local audit history without modifying backups. | `DeviceBackupReviewScanner`, `DeviceBackupReviewReport`, `reclaimer device-backups`, app Device Backups Review |
| Review Trash | Report the configured user Trash root, permission state, total size, largest immediate Trash items, Finder guidance, and local audit history without emptying or restoring anything. | `TrashReviewScanner`, `TrashReviewReport`, `reclaimer trash`, app Trash Review |
| Review apps & leftovers | Parse installed `.app` bundles and related Library files, then surface support data and orphan candidates as review-only guidance. | `AppReviewScanner`, `reclaimer apps`, app Apps & Leftovers |
| Preview and confirm app uninstall | Build a selected-app uninstall checklist/report, then optionally move only the selected app bundle to Trash after a clean dry run and explicit confirmation. Related support files remain review-only. | `AppUninstallPreview`, `AppUninstallExecutor`, `reclaimer apps uninstall-preview`, `reclaimer apps uninstall`, app Uninstall Preview |
| Review AI-agent storage | Scan common Codex, Claude, Cursor, Windsurf, and Ollama roots, then bucket cache/log churn separately from valuable history, protected state, and manual review. | `AgentStorageReviewBuilder`, `DefaultScopes.aiAgentStorage`, `reclaimer agents`, app AI Agent Storage |
| Review AI-agent retention | Apply conservative, balanced, or aggressive report-only retention profiles so old cache can become cleanup-plan guidance, old history can become compression-review guidance, and protected state stays blocked. | `AgentRetentionBuilder`, `AgentRetentionProfile`, `reclaimer agents retention`, app AI Agent Storage |
| Inspect in native tools | Copy path, reveal in Finder, Quick Look, and open Terminal for reviewed findings. | app finding action buttons |
| Protect valuable data | Default preserve/never-touch for user documents, creative assets, credentials, browser profiles, VM/container state, and Codex history. | rule pack and executor protected-class checks |
| Handle active files | Check open handles before planning/execution, surface process names in an active-handle review, and skip active paths. | `LsofOpenFileChecker`, `ActiveFileReviewScanner`, `PlanBuilder`, `ReclaimerExecutor`, `reclaimer active`, app Active Handles |
| Avoid blind deletes | Build a dry-run plan first; UI exposes dry-run receipts and enables reclaim only after a clean dry run. | `ReclaimPlan`, `ExecutionReceipt`, app Dry Run/Reclaim |
| Export receipts | Convert saved dry-run/execution receipts into local Markdown with action counts, before/after free-space fields, skipped/errors, optional path privacy controls, and non-claims. | `ExecutionReceiptReportBuilder`, `ReportPrivacyOptions`, `reclaimer receipts export`, app Audit History export |
| Reclaim safely | Use Trash for uncertain/user-visible data, direct delete only for allowlisted caches, compression only for cold files, holding area for reversible moves, with app confirmation before execution. | `ReclaimerExecutor`, app Reclaim confirmation |
| Restore held items | Store holding metadata so held items can be listed, restored, or expired after review. | `HoldingStore`, `reclaimer holding`, app Holding Area |
| Review recovery | Combine app-held items and saved receipts into a recovery view that separates Ryddi-restorable items from Trash review, dry-run/skipped no-ops, native-tool guidance, and non-recoverable direct deletes. | `RecoveryCenter`, `reclaimer recovery`, app Recovery Center |
| Prefer native cleanup | Report Docker/Colima/package-manager cleanup as native-tool receipts with command, purpose, risk, expected effect, audit save support, and explicit non-claims; execute only one selected non-destructive/non-placeholder command at a time with dry-run default and a local receipt. | `NativeToolGuidance`, `NativeToolExecutor`, `reclaimer native`, `reclaimer native run`, app native receipt preview |
| Inventory containers | Run bounded read-only Docker/Colima inspection commands and record storage buckets, images, containers, volumes, profiles, missing/not-running states, and command outcomes. | `ContainerInventoryScanner`, `reclaimer containers`, app Container Inventory |
| Automate conservatively | Scheduled jobs are report-only, can target Developer/General/All presets, built-in templates, or saved scope sets, and can be previewed before installation; unattended destructive cleanup is not enabled in v1. | `ScheduleConfiguration`, `LaunchAgentManager`, `ReclaimerAgent`, `schedule preview`, `schedule install` |
| Keep local audit trail | Save plans, receipts, native reports, container reports, active-file reports, and general review reports under Application Support with local-only JSON. | `AuditStore`, app Audit History |
| Package for direct distribution | Build an unsigned developer preview or signed app bundle, verify release-shaped artifacts, create checksum/manifest output, and leave notarization as an explicit credentialed step. | `Scripts/package-app.sh`, `Scripts/release-check.sh`, `Scripts/notarize-app.sh`, release-preview workflow |
| Stay private | No telemetry, cloud upload, or remote AI analysis. | architecture and README policy |

## MVP Feature Boundaries

Included:

- General Mac scan preset for Downloads, Desktop, personal folder review, user caches/logs, app support, attachments, device backups, and Trash review.
- Built-in scope templates for weekly general review, personal large-file review, app leftovers, browser caches, package caches, project dependencies, Xcode review, device backups, AI-agent storage, and developer maintenance.
- Sortable/groupable top-offender table for general cleanup and developer cleanup scans, including confidence and estimated immediate reclaim.
- Shared review queues for Safe Maintenance, Quit App First, Use Native Tool, Valuable History, Personal/App Assets, and Unknown findings, including single-queue CLI reports and app row-to-detail navigation.
- Saved custom scope sets for repeatable general cleanup, project-specific review, and developer maintenance scans, with local JSON import/export.
- Codex storage policy: caches/temp/logs versus sessions/state/credentials.
- Docker/Colima reporting and native cleanup guidance.
- Native-tool preview receipts for Docker/Colima/Homebrew/package-manager cleanup, plus one-command execution receipts for selected non-destructive/non-placeholder commands; no automatic native command execution.
- Read-only Docker/Colima live inventory for native storage estimates and profile/object context.
- Local user protections and exclusions, plus user path policy JSON import/export.
- Local user rule-pack preview/import/export for custom review/protection signals, disabled by default unless a scan passes `--include-user-rules` or the app User Rules scan toggle is on.
- Xcode Review for DerivedData, module/documentation caches, Products, Archives, DeviceSupport, simulator devices, runtimes, logs, preview simulator data, protected developer-state roots, Xcode/simctl guidance, audit saving, and no Xcode-state mutation.
- Xcode and package-manager cache classification.
- SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter developer cache review.
- Proportional visual map by category plus a bounded hierarchical disk drill-down.
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
- Large-file and old-file review mode with review-only signals, concrete row actions, category/safety summaries, and no automatic cleanup permission.
- Archive-candidate review checklists for large/old personal cleanup candidates, with redacted Markdown export and no automatic compression, Trash, or delete action.
- Duplicate-file review for explicit CLI paths and bounded app scans, with preserve-by-default files excluded unless requested.
- Trash Review for the current user Trash root, including largest items, permission state, Finder guidance, audit saving, and no empty-Trash execution.
- Downloads Review for old downloads, installers, archives, app bundles, permission state, Finder guidance, audit saving, and no move/delete execution.
- Browser Cache Review for cache roots, browser/cache-kind summaries, protected profile roots, quit-first guidance, audit saving, and no browser/profile mutation.
- Package Cache Review for package-manager cache roots, package-manager/cache-kind summaries, protected config/auth paths, native cleanup guidance, audit saving, and no package-manager mutation.
- Project Dependencies Review for project-local dependency/build artifact roots, ecosystem/kind/VCS summaries, protected project roots, native rebuild command hints, audit saving, and no project/source/manifest mutation.
- Xcode Review for Xcode cache, archive, device-support, simulator, runtime, log, preview, and protected developer-state roots, audit saving, and no Xcode mutation.
- Device Backups Review for local MobileSync backup size, age, encryption, metadata, Apple/Finder guidance, audit saving, and no backup mutation.
- Apps & Leftovers review for installed app support files and heuristic orphan candidates.
- App uninstall preview/checklist plus explicit app-bundle Trash execution after dry run and confirmation, keeping related support files review-only and outside execution.
- AI-agent storage review for Codex, Claude, Cursor, Windsurf, and Ollama, with cache/history/protected-state buckets and no automatic session/config/model cleanup.
- AI-agent retention profiles for conservative, balanced, or aggressive report-only guidance; profiles never delete sessions, memories, config, credentials, model state, or unknown state.
- Stale temp/scratch classification.
- App overview, sortable top offenders, shared review queues, Large & Old Files, owner summaries, rule catalog, permission coverage, APFS notes, item detail, feature matrix, dry-run plan, audit history, and settings copy.

Deferred:

- Automatic duplicate cleanup, smart duplicate selection, similar-file matching, and Photos/Music duplicate management.
- Automatic app-support cleanup, smart leftover deletion, bulk app uninstall, and vendor uninstaller execution.
- Malware scanning.
- App updater.
- RAM/performance optimizer features.
- Root helper or system-wide cleanup.
- Mac App Store sandbox packaging.
- Automatic deletion of safe-after-condition or review-required items.
- Automatic execution of native Docker/Colima/Homebrew/package-manager cleanup commands.
- Raw deletion or unattended execution of Docker/Colima VM disks, volumes, package stores, destructive prune/reset commands, or placeholder commands.
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
- `reclaimer overview --sort reclaim --group safety` reports grouped top offenders with confidence, conservative immediate-reclaim estimates, permission coverage, category summaries, owner summaries, and APFS notes.
- `reclaimer queues --path FIXTURE --limit 5 --json` reports all review queues with counts, allocated bytes, conservative reclaim estimates, sample rows, and non-claims without creating a cleanup plan.
- `reclaimer queues --path FIXTURE --queue unknown --limit 25 --json` reports one review queue with full queue accounting, bounded rows, guidance, and non-claims.
- `reclaimer large --path FIXTURE --min-size 1 --large-threshold 16000 --old-days 30 --json` reports large/old review rows, signal/category/safety summaries, concrete child rows where available, and non-claims without selecting cleanup.
- `reclaimer archive --path FIXTURE --min-size 1 --large-threshold 16000 --old-days 30 --json` reports archive checklist recommendations, recommendation summaries, candidate bytes, and non-claims without compressing, moving, Trashing, deleting, or selecting cleanup.
- `reclaimer archive --path FIXTURE --path-style redacted --output ARCHIVE.md` writes a local Markdown archive checklist without full local paths and without executing cleanup.
- `reclaimer drilldown --path FIXTURE --min-size 1 --max-depth 4 --tree-depth 4 --json` reports hierarchical scan nodes, omitted-child summaries, and non-claims without creating plan items.
- `reclaimer browsers --path FIXTURE/Library/Caches/Google/Chrome --home FIXTURE --json --save-audit` reports cache roots, protected profile roots, browser/cache-kind summaries, and non-claims without mutating cache or profile files.
- `reclaimer packages --home FIXTURE --json --save-audit` reports package-manager cache roots, protected config/auth paths, package-manager/cache-kind summaries, native cleanup guidance, and non-claims without mutating package-manager files.
- `reclaimer projects --path FIXTURE/Projects --json --include-vcs-status --save-audit` reports project-local dependency and build artifact folders, protected project roots, ecosystem/kind/VCS summaries, native rebuild command hints, and non-claims without mutating source, manifests, lockfiles, env files, credentials, IDE settings, dependencies, or build outputs.
- `reclaimer xcode --home FIXTURE --json --save-audit` reports Xcode cache, archive, DeviceSupport, simulator, runtime, log, preview, and protected developer-state roots, saves a local audit record, and does not mutate Xcode files.
- `reclaimer rules --json` reports the bundled rule version, safety/action/category summaries, rule sections, match hints, conditions, recovery notes, and non-claims without scanning or executing cleanup.
- `reclaimer scopes saved add/list/show/export/import` stores reusable scan roots locally, supports merge/replace import, and keeps non-claims that scope sets do not change cleanup safety.
- `reclaimer scopes templates list/show/save` exposes built-in guided templates, can materialize a template into a saved scope set, and keeps non-claims that templates do not change cleanup safety.
- `reclaimer scan --template weekly-general` scans the template roots while preserving all normal rules, policies, dry-run gates, and never-touch protections.
- `reclaimer scan --scope-set NAME` scans the saved roots while preserving all normal rules, policies, dry-run gates, and never-touch protections.
- `reclaimer schedule preview --preset general --kind evidence`, `reclaimer schedule preview --template weekly-general`, and `reclaimer schedule preview --scope-set NAME` print the exact report-only LaunchAgent plist without installing it.
- `reclaimer schedule install --template weekly-general` or `--scope-set NAME` writes a per-user LaunchAgent for that scope and still only runs `plan --json --save-audit` unless evidence reports are explicitly selected.
- `reclaimer rules user preview RULES.json --json` validates custom rules, rejects cleanup-granting rules, and reports import non-claims without mutating local config.
- `reclaimer rules user import RULES.json --json` stores local user rules without enabling them by default.
- `reclaimer scan --include-user-rules --path FIXTURE --min-size 1 --json` includes accepted user rules while preserving bundled never-touch protections.
- App Rule Catalog can preview, validate, import, export, and reveal local user rule packs; app scans only include user rules when the toolbar User Rules toggle is on.
- `reclaimer explain PATH --json --min-size 1` emits a structured explanation with what/why/risk/action/recovery/condition/next-step sections and non-claims without executing cleanup.
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
- `reclaimer trash --path FIXTURE/.Trash --json --save-audit` reports Trash size/largest items, saves a local audit record, and does not empty, restore, move, or delete files.
- `reclaimer device-backups --home FIXTURE --json --save-audit` reports local MobileSync backup size, age, encryption, parsed/missing metadata, saves a local audit record, and does not mutate backups.
- `reclaimer apps --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1` reports installed app support files and orphan candidates without creating plan items.
- `reclaimer apps uninstall-preview --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --output PREVIEW.md` writes an uninstall preview where the app bundle is separated from review-only related files and no deletion occurs.
- `reclaimer apps uninstall --dry-run --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --json` writes an app-uninstall receipt showing that only the selected app bundle would move to Trash.
- `reclaimer apps uninstall --yes --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --json` moves only the selected app bundle to Trash after open-file checks, user policy checks, and final bundle protection checks; related support files remain untouched.
- `reclaimer agents --path FIXTURE --min-size 1 --max-depth 4 --json` reports AI-agent storage buckets, including reclaimable cache, valuable history, protected state, and quit-first data without creating plan items.
- `reclaimer agents retention --path FIXTURE --profile balanced --min-size 1 --max-depth 4 --json` reports cleanup-plan, compression-review, keep, and protect recommendations without deleting, compressing, moving, or modifying agent files.
- `reclaimer native --path FIXTURE --json` emits native-tool preview receipts for matching Docker/Colima/package-manager findings and can save them to local audit history.
- `reclaimer native run --command-id brew.preview --path FIXTURE --dry-run --json --save-audit` creates a local native command execution receipt without executing the command.
- `reclaimer containers --json --timeout 2` emits a read-only Docker/Colima inventory, classifies missing versus not-running tools, and never emits prune/delete/stop/reset commands.
- `reclaimer policy protect/exclude/list/remove/export/import` writes local-only path policy, protects configured paths from cleanup selection, excludes configured paths from scan output, exports a versioned JSON document, imports by merge by default, and supports explicit `--replace`.
- Visual map accounting does not double-count nested directory findings.
- Owner summaries do not double-count nested directory findings and prefer explicit owner hints over category fallback.
- Large/old file review rows remain review-only and are not selected by an auto-safe plan.
- Archive review rows remain review-only and do not execute compression, Trash, delete, or holding-area actions.
- Duplicate review findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
- Apps & Leftovers findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
- App uninstall receipts can move only the selected app bundle to Trash; related support files remain outside `PlanBuilder`, `ReclaimerExecutor`, and app-uninstall execution.
- Device Backups Review remains report-only and never emits cleanup-plan selections or backup deletion actions.
- Xcode Review remains report-only and never emits cleanup-plan selections, raw simulator reset/delete actions, archive deletion actions, runtime deletion actions, or Xcode developer-state mutations.
