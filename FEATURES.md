# Ryddi Feature Matrix

Ryddi is intentionally not a scary one-click "clean my Mac" button. It is an evidence-first general Mac reclaim assistant, with developer and AI-agent storage cleanup as the first deep rule pack.

Release train: `v0.3.1` is published history and `v0.4.0 (5)` is the Guided Map release candidate. Unsigned local artifacts are developer previews, not releases.

## Guided Map Regular-User Experience

The v0.4 app starts with a user-initiated scan and a proportional treemap backed by the existing bounded drill-down evidence. Home shows one primary action and at most three ranked suggestions. Explore adds treemap/outline switching, search, category, and minimum-size filters. History keeps receipts, audits, and recovery evidence together. Advanced reports and configuration remain available in Settings.

The Guided Map is display-only: selecting or drilling into a map node never selects cleanup. Every cleanup review begins empty, and only explicit finding selections are passed into the existing plan, dry-run, one-use authorization, Trash, receipt, and verification gates. A cancelled, failed, or stale refresh cannot replace the last trustworthy completed map.

## Needed MVP Features And Chosen Solutions

| Feature | Best MVP solution | Implemented |
| --- | --- | --- |
| Choose scan scope | Named presets for Developer, General Mac, and All roots, built-in guided templates, explicit custom `--path` support, saved scope sets, and scope preview. | `ScanScopePreset`, `ScopeTemplateCatalog`, `ScanScopePlan`, `SavedScopeSetStore`, `DefaultScopes`, `reclaimer scopes`, app Scan Scope, app Scope Sets |
| Find large offenders | Bounded filesystem scanner over preset or custom roots, with permission evidence. | `FileScanner`, `DefaultScopes`, `reclaimer scan` |
| Show top offenders | Shared overview analytics with sortable/groupable rows by category, owner/app/tool, safety, scope, age, action, logical size, allocated size, confidence, and conservative reclaim estimate. | `TopOffenderTable`, `FindingAnalytics`, `reclaimer overview --sort --group`, app Top Offenders |
| Organize review queues | Shared user-intent queues separate safe maintenance, quit-first data, native-tool stores, valuable history, protected personal/app assets, and unknown review items, with single-queue filtering and evidence-detail navigation. | `ReviewQueueReport`, `ReviewQueueDetailReport`, `FindingAnalytics.reviewQueueReport`, `reclaimer queues --queue`, app Review Queues |
| Understand local cloud storage | User-started discovery for Dropbox, Google Drive, and explicitly selected MEGA roots; session-only confirmation; identity-revalidated, symlink-safe, bounded metadata inventory; logical-versus-local allocation totals; and review-only largest/oldest locally allocated files without opening file contents or hydrating placeholders. | `CloudStorageRootDiscovery`, `CloudStorageRootConfirmation`, `CloudLocalInventoryScanner`, app Cloud Storage workspace |
| Visualize space | A deterministic proportional Guided Map with treemap and accessible outline views, breadcrumbs, evidence state, inspector actions, and saved last-trustworthy display evidence; informational only, never a cleanup selector. | `GuidedMapSnapshot`, `GuidedMapBuilder`, `GuidedMapStore`, `TreemapLayout`, app Home and Explore |
| Explain ownership | Group non-overlapping findings by scanner owner hints or category fallback so users can see which app/tool appears responsible for storage. | `OwnerStorageSummary`, `ScanOverview.ownerSummaries`, `reclaimer overview`, app Top Owners, evidence reports |
| Track growth | Local scan snapshots compare category/scope/safety growth between scans and export local before/after Markdown reports; snapshots are retained for review rather than automatically pruned. | `ScanHistoryStore`, `GrowthReportBuilder`, `reclaimer history`, `reclaimer history report`, app Growth History |
| Watch disk pressure | Menu bar status item and CLI status report current free space using explicit warning/critical thresholds. | `DiskStatusReader`, `reclaimer status`, app menu bar |
| Show trust readiness | Summarize disk pressure, scan coverage, latest plan/receipt state, report-only automation, next-action buckets, release trust evidence, and explicit non-claims before raw cleanup navigation. | `TrustReadinessReport`, `TrustReadinessBuilder`, `reclaimer trust`, app Summary trust cards |
| Dogfood safely | Generate a redacted real-machine report that includes disk status, scan coverage, owners, queues, selected dry-run summary, active-handle summary, protected buckets, and explicit no-cleanup non-claims. | `DogfoodReportBuilder`, `reclaimer dogfood`, release-check smoke |
| Explain scan coverage | Report missing/restricted/readable scopes, degraded scan behavior, first-run Full Disk Access walkthrough steps, exportable guidance, and explicit permission non-claims. | `PermissionAdvisor`, `PermissionWalkthroughBuilder`, `reclaimer permissions`, `reclaimer permissions guide`, app Permissions |
| Explain storage truth | Keep logical bytes, allocated estimates, shared hard-link/clone state, bounded scan coverage, and observed post-action free-space deltas distinct; never turn a folder-size estimate into an exact reclaim promise. | `StorageAccounting`, `ScanCoverage`, `FilesystemLinkInspector`, `NativeActionReceipt`, `ScanOverview` |
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
| Review Downloads | Report old downloads, installers, archives, app bundles, kind/workflow summaries, largest items, Finder review steps, app row actions, and local audit history without moving or deleting files. | `DownloadsReviewScanner`, `DownloadsReviewReport`, `reclaimer downloads`, app Downloads Review |
| Review browser caches | Report browser cache roots, browser/cache-kind summaries, largest cache items, protected profile roots, advisory browser runtime status, and quit-first guidance without quitting browsers or modifying cache/profile state. | `BrowserCacheReviewScanner`, `BrowserCacheReviewReport`, `reclaimer browsers`, app Browser Cache Review |
| Review package caches | Report Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, and Playwright cache roots, package-manager/cache-kind summaries, largest cache items, protected config/auth paths, and native cleanup guidance without modifying package-manager state. | `PackageCacheReviewScanner`, `PackageCacheReviewReport`, `reclaimer packages`, app Package Cache Review |
| Review project dependencies | Report project-local dependency and build artifact folders such as node_modules, Python virtual environments, Swift .build, Rust target, Pods, .dart_tool, framework caches, Gradle, Flutter, and Android outputs while protecting source, manifests, lockfiles, env files, credentials, IDE settings, and unknown project state. Optional local VCS status, saved per-project review policies, detected project tools, workspace/monorepo evidence, bounded package.json script command previews, script-risk summaries, and gated command hints add review context without executing cleanup. | `ProjectDependencyReviewScanner`, `ProjectDependencyReviewReport`, `ProjectDependencyPolicyStore`, `ProjectDependencyToolingInfo`, `ProjectDependencyScriptInfo`, `ProjectDependencyWorkspaceInfo`, `reclaimer projects`, app Project Dependencies |
| Review Xcode storage | Report DerivedData, module/documentation caches, Products, Archives, DeviceSupport, simulator devices, runtimes, logs, preview simulator data, protected Xcode developer-state roots, and Xcode/simctl guidance without modifying Xcode state. | `XcodeReviewScanner`, `XcodeReviewReport`, `reclaimer xcode`, app Xcode Review |
| Review device backups | Report local iPhone/iPad MobileSync backup roots, size, age, encryption state, parsed metadata, missing metadata, Apple/Finder guidance, and local audit history without modifying backups. | `DeviceBackupReviewScanner`, `DeviceBackupReviewReport`, `reclaimer device-backups`, app Device Backups Review |
| Review Trash | Report the configured user Trash root, permission state, total size, largest immediate Trash items, Finder guidance, and local audit history without emptying or restoring anything. | `TrashReviewScanner`, `TrashReviewReport`, `reclaimer trash`, app Trash Review |
| Review apps & leftovers | Parse installed `.app` bundles and related Library files, then surface support data and orphan candidates as review-only guidance. | `AppReviewScanner`, `reclaimer apps`, app Apps & Leftovers |
| Preview app uninstall | Build a selected-app uninstall checklist/report and dry-run evidence for manual Finder removal. Related support files remain review-only. | `AppUninstallPreview`, `AppUninstallExecutor`, `reclaimer apps uninstall-preview`, `reclaimer apps uninstall --dry-run`, app Uninstall Preview |
| Review AI-agent storage | Scan common Codex, Claude, Cursor, Windsurf, and Ollama roots, then bucket cache/log churn separately from valuable history, protected state, and manual review. | `AgentStorageReviewBuilder`, `DefaultScopes.aiAgentStorage`, `reclaimer agents`, app AI Agent Storage |
| Review AI-agent retention | Apply conservative, balanced, or aggressive report-only retention profiles so old cache can become cleanup-plan guidance, old history can become compression-review guidance, and protected state stays blocked. | `AgentRetentionBuilder`, `AgentRetentionProfile`, `reclaimer agents retention`, app AI Agent Storage |
| Inspect in native tools | Copy path, reveal in Finder, Quick Look, and open Terminal for reviewed findings. | app finding action buttons |
| Protect valuable data | Default preserve/never-touch for user documents, creative assets, credentials, browser profiles, VM/container state, and Codex history. | rule pack and executor protected-class checks |
| Handle active files | Check open handles before planning/execution, surface process names in an active-handle review, and skip active paths. | `LsofOpenFileChecker`, `ActiveFileReviewScanner`, `PlanBuilder`, `ReclaimerExecutor`, `reclaimer active`, app Active Handles |
| Avoid blind deletes | Build a current dry-run plan first. Direct deletion remains disabled; selected auto-safe Trash actions require a matching clean receipt, one-time identity-bound authorization, exact-path confirmation, and final-state checks. | `ReclaimPlan`, `ExecutionReceipt`, `TrashExecutionAuthorization`, app Dry Run/Confirm |
| Export receipts | Convert saved dry-run/execution receipts into local Markdown with action counts, before/after free-space fields, skipped/errors, optional path privacy controls, and non-claims. | `ExecutionReceiptReportBuilder`, `ReportPrivacyOptions`, `reclaimer receipts export`, app Audit History export |
| Recoverable cleanup evidence | Keep direct cache deletion, compression, hold moves, and issue-package replacement disabled. Explicitly confirmed auto-safe cleanup actions and separately reviewed Ryddi-owned audit/history retention can move only still-matching eligible items to Finder Trash; each action records its result. | `ReclaimerExecutor`, `TrashExecutionReadiness`, `AuditStore`, `ScanHistoryStore`, app Action Center and Recovery Center |
| Review holding records | List holding metadata and reveal held paths in Finder for manual recovery; Ryddi does not restore or expire them automatically. | `HoldingStore`, `reclaimer holding`, app Holding Area |
| Review recovery | Combine holding records and saved receipts into a recovery view that separates manual Finder recovery from Trash review, dry-run/skipped no-ops, native-tool guidance, and manual core-action outcomes. | `RecoveryCenter`, `reclaimer recovery`, app Recovery Center |
| Prefer native cleanup | Report Docker/Colima/package-manager cleanup as native-tool receipts with command, purpose, risk, expected effect, audit save support, and explicit non-claims. Only Homebrew cleanup, Docker builder prune, and npm cache clean have narrow same-process preview/perform lanes; broad Docker, VM, volume, project, and package-store actions remain guidance-only. | `NativeToolGuidance`, `NativeMaintenanceExecutor`, `NativeToolExecutor`, `NativeActionExecutor`, `reclaimer native`, app native receipt preview |
| Inventory containers | Run bounded read-only Docker/Colima inspection commands and record storage buckets, images, containers, volumes, profiles, missing/not-running states, and command outcomes. | `ContainerInventoryScanner`, `reclaimer containers`, app Container Inventory |
| Review remote SSH/VPS targets | Use the system SSH client and existing SSH config to collect bounded, read-only disk evidence from Linux VPS targets, label scan coverage as complete/partial/unreachable/unsupported with row-level reasons, classify storage buckets conservatively, emit native guidance and manual command cards, export redacted reports, compare saved reachable remote scan growth locally, and save local audit records without remote cleanup. | `RemoteTargetResolver`, `RemoteSSHCommandRunner`, `RemoteProbeBuilder`, `RemoteScanBuilder`, `RemoteScanCoverageBuilder`, `RemoteCommandCardBuilder`, `RemoteReportBuilder`, `RemoteGrowthReportBuilder`, `reclaimer remote`, app Remote Targets |
| Package redacted issue evidence | Write a small local diagnostics folder with manifest, report, non-claims, local audit/session summary, and optional redacted remote summary without copying raw SSH config, keys, tokens, or arbitrary audit JSON. User-selected export files must be new and issue-package directories must be new or empty; existing paths are never replaced. | `IssuePackageExporter`, `SafeFileOutput`, `RemotePrivacyRedactor`, `reclaimer issue package` |
| Automate conservatively | Scheduled jobs use the packaged `reclaimer` CLI in report-only mode, can target Developer/General/All presets, built-in templates, or saved scope sets, and can be previewed before installation; unattended destructive cleanup is not enabled in v1. Ryddi refuses to overwrite or remove an existing schedule plist. | `ScheduleConfiguration`, `LaunchAgentManager`, `schedule preview`, `schedule install` |
| Keep local audit trail | Save private-permission plans, receipts, native reports, container reports, active-file reports, and review reports under Application Support. Dry-run-first retention can explicitly move only still-matching known JSON records to Finder Trash; it is never scheduled. | `AuditStore`, `AuditRetentionPolicy`, app Audit History |
| Package for direct distribution | Build unsigned previews for testing, or fail-closed signed release artifacts that require Developer ID signing, notarization, stapling, Gatekeeper assessment, strict codesign verification, checksum, and typed manifest proof. | `Scripts/package-app.sh`, `Scripts/release-check.sh`, `Scripts/notarize-app.sh`, `reclaimer release-trust`, release-preview and signed-release workflows |
| Present as a native Mac app | Package a validated multi-resolution Ryddi fan icon in the signed app bundle for Finder, Dock, About, and app-switcher presentation. | `Assets/Ryddi.icns`, `Assets/AppIcon.iconset`, `Scripts/generate-app-icon.swift` |
| Keep Ryddi current | Check a signed HTTPS appcast automatically once per day, let users disable background checks, and expose **Update to Latest Version** in Settings and the Ryddi menu. Update archives and the feed require Sparkle EdDSA signatures in addition to Developer ID signing and notarization. | `RyddiUpdateController`, Sparkle 2.9.4, `appcast.xml`, `Scripts/generate-appcast.sh` |
| Verify the packaged app safely | Launch the packaged app against a temporary fixture, expose stable accessibility identifiers, prove scan/plan/dry-run/explicit-confirmation/Trash flow, capture three window sizes, clean the receipt-identified test Trash artifact, and verify protected fixtures remain byte-identical. | `Scripts/make-app-e2e-fixture.sh`, `Scripts/app-e2e-smoke.sh`, `Scripts/run-packaged-app-e2e.sh`, `RyddiAXHarness`, `AppAccessibilityContractTests`, `AppE2EFixtureTests`, `AppLayoutContractTests` |
| Stay private | No telemetry, cloud upload, or remote AI analysis. | architecture and README policy |
| Diagnose slow workflows locally | Record privacy-safe unified-log timings/counts and explicitly export a bounded local JSON summary without paths, command output, file contents, or automatic upload. | `DiagnosticMetadata`, `RyddiLog`, `Export Diagnostic Summary`, redaction tests |

## MVP Feature Boundaries

Included:

- General Mac scan preset for Downloads, Desktop, personal folder review, user caches/logs, app support, attachments, device backups, and Trash review.
- Built-in scope templates for weekly general review, personal large-file review, app leftovers, browser caches, package caches, project dependencies, Xcode review, device backups, AI-agent storage, and developer maintenance.
- Sortable/groupable top-offender table for general cleanup and developer cleanup scans, including confidence and estimated immediate reclaim.
- Shared review queues for Safe Maintenance, Quit App First, Use Native Tool, Valuable History, Personal/App Assets, and Unknown findings, including single-queue CLI reports and app row-to-detail navigation.
- Saved custom scope sets for repeatable general cleanup, project-specific review, and developer maintenance scans, with local JSON import/export.
- Codex storage policy: caches/temp/logs versus sessions/state/credentials.
- Docker/Colima reporting and native cleanup guidance.
- Native-tool preview receipts for Docker/Colima/Homebrew/package-manager cleanup, plus narrow same-process execution lanes for Homebrew cleanup, Docker builder prune, and npm cache clean after fresh previews; broad Docker, Colima, VM, volume, project, and package-store cleanup remains guidance-only.
- Read-only Docker/Colima live inventory for native storage estimates and profile/object context.
- Agentless Remote Targets for SSH/VPS report-only review: SSH alias discovery, safe probe, Linux VPS disk/inode evidence, row-level coverage, journald/APT/Docker/deploy-release/large-file/temp buckets, native guidance, manual command cards, redacted Markdown export, saved remote growth history, local audit history, and no remote cleanup execution.
- Redacted issue package export for local support/debug evidence without copying raw SSH config, private keys, tokens, or arbitrary audit JSON.
- Local user protections and exclusions, plus user path policy JSON import/export.
- Local user rule-pack preview/import/export for custom review/protection signals, disabled by default unless a scan passes `--include-user-rules` or the app User Rules scan toggle is on.
- Xcode Review for DerivedData, module/documentation caches, Products, Archives, DeviceSupport, simulator devices, runtimes, logs, preview simulator data, protected developer-state roots, Xcode/simctl guidance, audit saving, and no Xcode-state mutation.
- Xcode and package-manager cache classification.
- SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter developer cache review.
- Proportional visual map by category plus a bounded hierarchical disk drill-down.
- Local scan history and growth deltas.
- Exportable local Markdown growth reports for saved snapshot comparisons.
- Menu bar disk-pressure status with report-only scan shortcut.
- Trust readiness cockpit and CLI report for disk pressure, permissions, dry-run/receipt state, automation, next-action buckets, and release trust evidence.
- Dogfood report mode for redacted, no-cleanup real-machine evidence packages.
- Exportable local Markdown evidence reports.
- Exportable local Markdown reclaim plan reports.
- Exportable local Markdown execution receipt reports.
- Recovery Center for manual Finder holding-record recovery and receipt-based guidance.
- Report path privacy controls: full, home-relative, redacted, plus user-entered reason redaction.
- Active-handle review with process summaries for cleanup-relevant candidates.
- Permission advisor and first-run walkthrough for readable/denied/missing scope coverage, Full Disk Access guidance, degraded-mode labels, rescan commands, and permission non-claims.
- Browser cache versus browser profile distinction.
- Large-file and old-file review mode with review-only signals, concrete row actions, category/safety summaries, and no automatic cleanup permission.
- Archive-candidate review checklists for large/old personal cleanup candidates, with redacted Markdown export and no automatic compression, Trash, or delete action.
- Duplicate-file review for explicit CLI paths and bounded app scans, with preserve-by-default files excluded unless requested.
- Trash Review for the current user Trash root, including largest items, permission state, Finder guidance, audit saving, and no empty-Trash execution.
- Downloads Review for old downloads, installers, archives, app bundles, permission state, Finder workflow buckets, row actions, audit saving, and no move/delete execution.
- Browser Cache Review for cache roots, browser/cache-kind summaries, protected profile roots, advisory browser runtime status, quit-first guidance, audit saving, and no browser/profile mutation.
- Package Cache Review for package-manager cache roots, package-manager/cache-kind summaries, protected config/auth paths, native cleanup guidance, audit saving, and no package-manager mutation.
- Project Dependencies Review for project-local dependency/build artifact roots, ecosystem/kind/tool/script/script-risk/VCS/policy summaries, protected project roots, saved per-project review/preserve/skip policies, bounded/redacted package.json script command previews, native rebuild command hints gated away from destructive/lifecycle/deploy/network scripts, audit saving, and no project/source/manifest/script execution or mutation.
- Xcode Review for Xcode cache, archive, device-support, simulator, runtime, log, preview, and protected developer-state roots, audit saving, and no Xcode mutation.
- Device Backups Review for local MobileSync backup size, age, encryption, metadata, Apple/Finder guidance, audit saving, and no backup mutation.
- Apps & Leftovers review for installed app support files and heuristic orphan candidates.
- App uninstall preview/checklist plus dry-run evidence for manual Finder removal, keeping related support files review-only and outside automatic mutation.
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
- Automatic or unattended deletion, Trash, compression, holding moves, audit pruning, or issue-package replacement. The only core perform lane is an interactive one-use move to Trash for current auto-safe selections.
- Automatic execution of native Docker/Colima/package-manager cleanup commands; Homebrew is limited to a fresh preview plus one-time same-process capability.
- Remote cleanup execution, remote Docker prune/reset execution, sudo password management, remote agent installation, secrets inventory, database cleanup, and unattended destructive SSH maintenance.
- Raw deletion or unattended execution of Docker/Colima VM disks, volumes, package stores, destructive prune/reset commands, or placeholder commands.
- Screenshot/GIF walkthrough for Full Disk Access onboarding in release materials.

## Acceptance Criteria

- `swift test --scratch-path .build` passes.
- `reclaimer plan --path ~/.codex --no-lsof` classifies Codex sessions as preserve/review, cache/temp as auto-safe, and credentials/state as never-touch.
- `reclaimer execute --dry-run` never mutates files.
- The app can complete Scan, Plan, Dry Run, Confirm, Trash, and Recovery for current auto-safe Trash selections; direct deletion and all non-Trash core actions remain disabled.
- `reclaimer holding expire` lists eligible holding records without deleting them; `holding restore` and `recovery restore` reject automatic moves and direct users to Finder.
- `Scripts/package-app.sh` produces `dist/Ryddi.app` with the bundled rule resources copied into the app bundle.
- `Scripts/release-check.sh` runs tests, builds `dist/Ryddi.app`, validates bundle layout/resources, smoke-tests the packaged CLI, records typed release-trust keys, and creates a zip/checksum/manifest.
- Signed releases also produce an app-only `Ryddi-vX.Y.Z-update.zip` for Sparkle. `Scripts/generate-appcast.sh` signs the archive entry and whole appcast with the Keychain-held EdDSA key; the private key is never stored in the repository.
- `RYDDI_VERSION=0.4.0 RYDDI_BUILD_NUMBER=5 RYDDI_RELEASE_SIGNING=required RYDDI_REQUIRE_PACKAGED_AX_E2E=1 RYDDI_ARTIFACT_BASENAME=Ryddi-v0.4.0 Scripts/release-check.sh` fails unless Developer ID signing, notarization, stapling, Gatekeeper assessment, strict codesign verification, packaged Accessibility E2E, checksum, bundle version `0.4.0`, build `5`, and manifest proof all pass.
- `reclaimer release-trust --json --manifest dist/Ryddi-release-manifest.txt` parses the manifest into exact states and does not treat `not notarized` as trusted.
- `reclaimer remote dogfood --from-audit TARGET --path-style redacted --output FILE.md` packages saved remote evidence without reconnecting to a server or running cleanup.
- `reclaimer issue package --path-style redacted --include-remote --output DIR` writes a share-reviewable local diagnostics folder with manifest, non-claims, local summary, and optional redacted remote summary.
- The app can scan, build a dry-run plan, show feature coverage, show item evidence, and show local audit history.
- `reclaimer overview --sort reclaim --group safety` reports grouped top offenders with confidence, conservative immediate-reclaim estimates, permission coverage, category summaries, owner summaries, and APFS notes.
- `reclaimer queues --path FIXTURE --limit 5 --json` reports all review queues with counts, allocated bytes, conservative reclaim estimates, sample rows, and non-claims without creating a cleanup plan.
- `reclaimer queues --path FIXTURE --queue unknown --limit 25 --json` reports one review queue with full queue accounting, bounded rows, guidance, and non-claims.
- `reclaimer large --path FIXTURE --min-size 1 --large-threshold 16000 --old-days 30 --json` reports large/old review rows, signal/category/safety summaries, concrete child rows where available, and non-claims without selecting cleanup.
- `reclaimer archive --path FIXTURE --min-size 1 --large-threshold 16000 --old-days 30 --json` reports archive checklist recommendations, recommendation summaries, candidate bytes, and non-claims without compressing, moving, Trashing, deleting, or selecting cleanup.
- `reclaimer archive --path FIXTURE --path-style redacted --output ARCHIVE.md` writes a local Markdown archive checklist without full local paths and without executing cleanup.
- `reclaimer drilldown --path FIXTURE --min-size 1 --max-depth 4 --tree-depth 4 --json` reports hierarchical scan nodes, omitted-child summaries, and non-claims without creating plan items.
- `reclaimer browsers --path FIXTURE/Library/Caches/Google/Chrome --home FIXTURE --json --save-audit` reports cache roots, protected profile roots, browser/cache-kind summaries, advisory browser runtime status, and non-claims without quitting browsers or mutating cache/profile files.
- `reclaimer packages --home FIXTURE --json --save-audit` reports package-manager cache roots, protected config/auth paths, package-manager/cache-kind summaries, native cleanup guidance, and non-claims without mutating package-manager files.
- `reclaimer projects policy skip-review FIXTURE/Projects/SkippedWeb --reason "release smoke"` saves a local per-project review policy, `reclaimer projects policy export/import` round-trips it, and `reclaimer projects --path FIXTURE/Projects --json --include-vcs-status --save-audit` reports project-local dependency and build artifact folders, protected project roots, ecosystem/kind/tool/script/script-risk/workspace/VCS/policy summaries, skipped-by-policy projects, detected package-manager/script command hints, workspace-inherited package-manager hints, bounded/redacted package.json command previews, and non-claims without mutating source, manifests, lockfiles, env files, credentials, IDE settings, workspace metadata, dependencies, build outputs, or executing project scripts.
- `reclaimer xcode --home FIXTURE --json --save-audit` reports Xcode cache, archive, DeviceSupport, simulator, runtime, log, preview, and protected developer-state roots, saves a local audit record, and does not mutate Xcode files.
- `reclaimer rules --json` reports the bundled rule version, safety/action/category summaries, rule sections, match hints, conditions, recovery notes, and non-claims without scanning or executing cleanup.
- `reclaimer scopes saved add/list/show/export/import` stores reusable scan roots locally, supports merge/replace import, and keeps non-claims that scope sets do not change cleanup safety.
- `reclaimer scopes templates list/show/save` exposes built-in guided templates, can materialize a template into a saved scope set, and keeps non-claims that templates do not change cleanup safety.
- `reclaimer scan --template weekly-general` scans the template roots while preserving all normal rules, policies, dry-run gates, and never-touch protections.
- `reclaimer scan --scope-set NAME` scans the saved roots while preserving all normal rules, policies, dry-run gates, and never-touch protections.
- `reclaimer schedule preview --preset general --kind evidence`, `reclaimer schedule preview --template weekly-general`, and `reclaimer schedule preview --scope-set NAME` print the exact report-only LaunchAgent plist without installing it.
- `reclaimer schedule install --template weekly-general` or `--scope-set NAME` writes a new per-user LaunchAgent for that scope and still only runs `plan --json --save-audit` unless evidence reports are explicitly selected; it refuses to replace an existing plist, which must be reviewed manually in Finder.
- `reclaimer rules user preview RULES.json --json` validates custom rules, rejects cleanup-granting rules, and reports import non-claims without mutating local config.
- `reclaimer rules user import RULES.json --json` stores local user rules without enabling them by default.
- `reclaimer scan --include-user-rules --path FIXTURE --min-size 1 --json` includes accepted user rules while preserving bundled never-touch protections.
- App Rule Catalog can preview, validate, import, export, and reveal local user rule packs; app scans only include user rules when the toolbar User Rules toggle is on.
- `reclaimer explain PATH --json --min-size 1` emits a structured explanation with what/why/risk/action/recovery/condition/next-step sections and non-claims without executing cleanup.
- `reclaimer permissions --json --path FIXTURE` reports coverage level, readable/denied/missing counts, recommended actions, and non-claims.
- `reclaimer trust --json --path FIXTURE` reports trust readiness, next-action counts, latest audit summary, typed release trust evidence, and non-claims without executing cleanup.
- `reclaimer dogfood --path FIXTURE --path-style redacted --output DOGFOOD.md` writes a redacted Markdown report and includes no-cleanup, no-permission-grant, and no-exact-APFS-reclaim non-claims.
- `reclaimer permissions guide --path FIXTURE --output GUIDE.md` writes a local Markdown first-run walkthrough with Full Disk Access steps, rescan/report-only commands, affected scopes, and non-claims.
- `reclaimer active --path FIXTURE --json` reports cleanup candidates blocked by open handles or failed open-file checks, with process summaries when available, and does not quit processes or execute cleanup.
- `reclaimer report --path FIXTURE --limit 5 --output REPORT.md` writes a local Markdown report with top findings, policy, accounting notes, and non-claims without executing cleanup.
- `reclaimer report --path FIXTURE --path-style redacted --redact-user-text --output REPORT.md` writes a share-safer Markdown report without full local paths or user-entered policy reasons.
- `reclaimer plan --path FIXTURE --output PLAN.md` writes a local Markdown reclaim plan report with selected actions, blocked/review items, safety buckets, estimates, and non-claims without executing cleanup.
- `reclaimer plans export --path-style redacted --output PLAN.md` exports a saved plan report with redacted action/review paths without mutating the saved plan.
- `reclaimer receipts export --output RECEIPT.md` writes a local Markdown report for a saved receipt without rerunning cleanup.
- `reclaimer receipts export --path-style redacted --output RECEIPT.md` redacts receipt action paths and path-bearing messages without mutating the saved receipt.
- `reclaimer recovery --json` reports holding records as manual Finder review, dry-run/skipped actions as no-op evidence, Trash actions as Finder Trash review, and manual core-action/native-tool outcomes as non-Ryddi recovery guidance.
- `reclaimer recovery restore HOLDING_ID --to DESTINATION` rejects automatic moves and preserves the held record for manual Finder review.
- `reclaimer status --json` reports disk pressure and free-space notes without scanning content.
- `reclaimer history record/list/diff/report/prune` stores local scan snapshots, reports category/scope/safety deltas, and offers explicit dry-run-first retention that moves only identity-matching old snapshots to Finder Trash.
- `reclaimer history report --output GROWTH.md` writes a local Markdown before/after report for saved scan snapshots, with category/scope/safety grouping, path privacy controls, and non-claims.
- `reclaimer duplicates --path FIXTURE --min-size 1` groups same-content regular files, skips protected paths, and emits review-only `openGuidance` candidates.
- `reclaimer trash --path FIXTURE/.Trash --json --save-audit` reports Trash size/largest items, saves a local audit record, and does not empty, restore, move, or delete files.
- `reclaimer device-backups --home FIXTURE --json --save-audit` reports local MobileSync backup size, age, encryption, parsed/missing metadata, saves a local audit record, and does not mutate backups.
- `reclaimer apps --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1` reports installed app support files and orphan candidates without creating plan items.
- `reclaimer apps uninstall-preview --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --output PREVIEW.md` writes an uninstall preview where the app bundle is separated from review-only related files and no deletion occurs.
- `reclaimer apps uninstall --dry-run --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --json` writes app-uninstall evidence for manual Finder removal; related files remain untouched.
- `reclaimer apps uninstall --yes ...` is rejected because Trash cannot be bound atomically to the reviewed app bundle.
- `reclaimer agents --path FIXTURE --min-size 1 --max-depth 4 --json` reports AI-agent storage buckets, including reclaimable cache, valuable history, protected state, and quit-first data without creating plan items.
- `reclaimer agents retention --path FIXTURE --profile balanced --min-size 1 --max-depth 4 --json` reports cleanup-plan, compression-review, keep, and protect recommendations without deleting, compressing, moving, or modifying agent files.
- `reclaimer native --path FIXTURE --json` emits native-tool preview receipts for matching Docker/Colima/package-manager findings and can save them to local audit history.
- `reclaimer native run --command-id brew.preview --path FIXTURE --dry-run --json --save-audit` runs the exact bounded Homebrew preview and captures its output in a local native command execution receipt.
- `reclaimer native homebrew cleanup --dry-run --finding-path FIXTURE/Library/Caches/Homebrew --json --save-audit` runs Homebrew's own preview command and saves the bounded output as a native command receipt.
- `reclaimer native run --command-id brew.cleanup --finding-path FIXTURE/Library/Caches/Homebrew --path FIXTURE --yes --save-audit` runs a new bounded preview and consumes its one-time same-process capability before the paired Homebrew cleanup; saved preview JSON remains evidence only.
- `reclaimer native receipts list/export` retrieves saved native command receipts and writes local Markdown reports without rerunning native tools.
- `reclaimer containers --json --timeout 2` emits a read-only Docker/Colima inventory, classifies missing versus not-running tools, and never emits prune/delete/stop/reset commands.
- `reclaimer remote history list/diff/report` reads saved reachable remote scan audit records, compares bucket/path growth, writes optional redacted Markdown, and never connects to or mutates a server.
- `reclaimer policy protect/exclude/list/remove/export/import` writes local-only path policy, protects configured paths from cleanup selection, excludes configured paths from scan output, exports a versioned JSON document, imports by merge by default, and supports explicit `--replace`.
- Visual map accounting does not double-count nested directory findings.
- Owner summaries do not double-count nested directory findings and prefer explicit owner hints over category fallback.
- Large/old file review rows remain review-only and are not selected by an auto-safe plan.
- Archive review rows remain review-only and do not execute compression, Trash, delete, or holding-area actions.
- Duplicate review findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
- Apps & Leftovers findings remain outside `PlanBuilder` and `ReclaimerExecutor`.
- App uninstall receipts remain evidence-only; the selected app bundle and related support files remain outside automatic mutation.
- Device Backups Review remains report-only and never emits cleanup-plan selections or backup deletion actions.
- Xcode Review remains report-only and never emits cleanup-plan selections, raw simulator reset/delete actions, archive deletion actions, runtime deletion actions, or Xcode developer-state mutations.
