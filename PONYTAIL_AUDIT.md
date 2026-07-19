# Ryddi Ponytail Audit — Full File-by-File Assessment

**Audit date:** 2026-07-19  
**Files:** 167 Swift files, 64,153 lines  
**Rebuild target:** ~600 lines across Clean/Offload/Control pillars

## Executive Summary

| Category | Files | Lines | Verdict |
|----------|-------|-------|---------|
| **DELETE** (unnecessary) | 62 | ~22,000 | Whole features, speculative code, dead abstractions |
| **SIMPLIFY** (collapse/one-liner) | 73 | ~30,000 | Over-engineered; stdlib or small functions replace |
| **KEEP** (needed, minimal) | 32 | ~12,000 | Core scan/trash/UI; can still be tightened |

---

## RUNG 1: DELETE — Does not need to exist at all

### RyddiProtectCore (entire target — 14 files, ~3,500 lines)
A cloud backup transfer feature that is 100% speculative. No shipped feature uses it.

| File | Reason |
|------|--------|
| `CloudContracts.swift` | Cloud provider protocols — YAGNI |
| `CloudInventoryBuilder.swift` (829 lines) | Building cloud file inventories — never called |
| `CloudLocalInventory.swift` (542 lines) | Local mirror of cloud state |
| `CloudOrganization.swift` | Organization modeling |
| `CloudRateLimiter.swift` | Rate limiting for cloud APIs |
| `CloudStorageRootDiscovery.swift` | Discovers cloud storage roots |
| `CloudTransfer.swift` | Transfer model types |
| `CloudTransferAuthorization.swift` | Auth for cloud transfers |
| `CloudTransferExecutor.swift` | Executes cloud transfers |
| `CloudTransferReceiptStore.swift` | Stores transfer receipts |
| `PKCE.swift` | PKCE auth flow — no cloud provider wired in |
| `ProtectionAssessment.swift` | "Assessment" types |
| `ProtectionIdentity.swift` | Identity types |
| `ProtectionRuleProposal.swift` | Rule proposal |
| `SecretSourceInventory.swift` (587 lines) | Secret scanning — speculative |

**Ponytail verdict:** Delete all 14 files. When cloud backup is a real requirement, add a single `rsync` wrapper.

### RyddiProtectAuth (entire target — 1 file, ~200 lines)
`ProviderCredentialStore.swift` — stores cloud provider credentials. No providers exist.

**Ponytail verdict:** Delete.

### Report/Export chain — 14 files, ~3,500 lines
Each review type has its own dedicated report file that is just a Codable data carrier.

| File | Reason |
|------|--------|
| `GrowthReportExport.swift` | Export growth reports |
| `PlanReportExport.swift` | Export plan reports |
| `ReceiptReportExport.swift` | Export receipt reports |
| `ReportExport.swift` | Generic export — only wraps JSONEncoder |
| `ReportPrivacy.swift` | Path privacy/redaction options |
| `IssuePackageExport.swift` (539 lines) | Export issue JSON |
| `DogfoodReport.swift` | Internal dogfooding report |
| `RemoteDogfoodReport.swift` | Remote dogfooding report |
| `RemoteGrowthReport.swift` (514 lines) | Remote growth report |
| `RemoteGrowthSummary.swift` | Summary for remote growth |
| `MarkdownTable.swift` (11 lines) | Markdown table formatting |
| `HomePresentation.swift` (219 lines) | Home screen layout data |
| `ScanPresentationSnapshot.swift` | Scan snapshot for display |
| `DiagnosticMetadata.swift` | Diagnostic metadata |

**Ponytail verdict:** `ReportExport.swift` is a one-liner: `JSONEncoder().encode(x)`. All others are spec report types with no consumer. Delete all 14. `MarkdownTable` is 11 lines that could be `data.map { "| \($0.joined(separator: " | ")) |" }.joined(separator: "\n")`.

### Finders/Review "Scanner" variants — 9 files, ~3,000 lines
Each review domain has its own scanner class with options, models, and report types — but they all do the same thing: walk a directory and classify files.

| File | Lines | What it actually does |
|------|-------|----------------------|
| `AppReview.swift` | 635 | Scan /Applications for large apps |
| `AppUninstallPreview.swift` | 851 | Preview app uninstall |
| `ArchiveReview.swift` | 502 | Review ~/Library archives |
| `BrowserCacheReview.swift` | 834 | Scan browser cache dirs |
| `DeviceBackupReview.swift` | 651 | Scan iOS backups |
| `DownloadsReview.swift` | 816 | Scan ~/Downloads |
| `DuplicateReview.swift` | 477 | Hash-based duplicate finder |
| `ProjectDependencyReview.swift` | 3028 | Scan node_modules, vendor, etc. |
| `XcodeReview.swift` | 749 | Scan Xcode caches |

**Ponytail verdict:** All nine are the same pattern: a `Scanner` subclass or wrapper that scans a specific directory. Collapse into one `TargetedScan` that takes a `URL` and `RuleEngine`. Delete all 9 specialized files. The only thing that varies is the path list, which is already in `DefaultScopes`.

### Container/Docker/Colima — 4 files, ~1,800 lines
| File | Lines | Reason |
|------|-------|--------|
| `ContainerInventory.swift` | 1176 | Docker/Colima container listing |
| `ColimaProfileInventory.swift` | ~200 | Colima profile inventory |
| `DockerVolumeRemoval.swift` | ~400 | Docker volume removal |
| `DiskDrillDown.swift` | 243 | Disk usage drill-down |

**Ponytail verdict:** `docker system df` is one command. `colima list` is one command. Delete all 4 files.

### Scheduling and History — 4 files, ~800 lines
| File | Reason |
|------|--------|
| `Scheduler.swift` | Cron-like scheduler for auto-scans — not wired in |
| `ScanHistoryStore.swift` | History store |
| `AuditStoreHygiene.swift` | Prunes old audit files |
| `AuditStoreSnapshot.swift` | Audit snapshot data |

**Ponytail verdict:** `Scheduler` is unused. History/hygiene/audit store are management overhead for a tool whose output is files on disk. Delete all 4.

### Permission Machinery — 3 files, ~400 lines
| File | Reason |
|------|--------|
| `PermissionAdvisor.swift` | Advises on permission coverage |
| `PermissionWalkthrough.swift` | Walkthrough wizard |
| `PermissionCoverageTransition.swift` | Transition between coverage states |

**Ponytail verdict:** macOS already has a permission dialog. `PermissionAdvisor` is a checker for what the scanning found. If a path is unreadable, report it — that's one `guard` in the scanner. Delete all 3.

### Agent Storage Retention — 2 files, ~880 lines
| File | Reason |
|------|--------|
| `AgentStorageReview.swift` (804 lines) | Reviews AI agent storage |
| `AgentRetentionPlan.swift` | Retention plan generation |

**Ponytail verdict:** Same as above — a specialized scan of AI agent directories. These are already in `DefaultScopes`. Delete both.

### Remote Scanning Infrastructure — 7 files, ~1,800 lines
| File | Reason |
|------|--------|
| `RemoteTarget.swift` (799 lines) | Remote SSH target model |
| `RemoteScan.swift` | Remote scan orchestration |
| `RemoteProbe.swift` | Probe remote host |
| `RemoteSSHCommandRunner.swift` | Run SSH commands |
| `RemoteCommandCard.swift` | Command card model |
| `RemoteParsers.swift` | Parse remote output |
| `RemotePrivacyRedactor.swift` | Redact private data from remote output |
| `RemoteTargetInputPolicy.swift` | Policy for target input |
| `KnownHostsInspector.swift` | Inspect known_hosts |

**Ponytail verdict:** Remote scanning is an entire feature that hasn't shipped. For a v1 disk reclaimer, scanning remote machines is YAGNI. Delete all 7 files. The "rebuild plan" keeps 3 pillars: Clean, Offload, Control — remote scanning is none of them.

### Misc Single-Use Data Carriers — 10 files, ~1,200 lines
| File | Reason |
|------|--------|
| `CurrentEvidence.swift` | Evidence wrapper type |
| `FilesystemLinkInspector.swift` | Symlink/hardlink inspector |
| `FindingExplanation.swift` | Explanation builder |
| `HoldingStore.swift` | Quarantine holding area |
| `OpenFileChecker.swift` | `lsof` wrapper |
| `ReleaseTrustEvidence.swift` | Trust evidence model |
| `RuntimeReleaseTrustProbe.swift` | Runtime probe |
| `TrustReadiness.swift` | Readiness checker |
| `GuidedWorkflow.swift` | Workflow step definitions |
| `RegenerableStorageCleanup.swift` | "Regenerable" cleanup category |

**Ponytail verdict:** Most are one-field structs or wrappers around one stdlib call. `OpenFileChecker` wraps `lsof`. `FilesystemLinkInspector` wraps `lstat`. `HoldingStore` is a directory copy. Delete all 10.

---

## RUNG 2-6: SIMPLIFY — Can be one line, stdlib, or already in codebase

### Models.swift → Collapse to 3 files (from 850 lines → ~100 lines)
**Current:** 850 lines with 24 types, 15 with manual Codable boilerplate.  
**Simplest:** Swift auto-synthesizes Codable for all structs with Codable fields. Delete every manual `init(from:)`/`encode(to:)` and `CodingKeys` enum. Keep only:
- `Finding` (the core type — but drop `storageAccounting`, `measurementCoverage`, `ruleMatches` as standalone fields; they're evidence)
- `SafetyClass` (5 cases → keep, used everywhere)
- `ActionKind` (keep)
- `PermissionState` (keep)
- `ScanScope` (keep)

`ByteFormat` → delete entirely. `ByteCountFormatter.string(fromByteCount:countStyle:)` is one line. Every `ByteFormat.string(x)` call becomes the stdlib call directly.

`ScanScopePreset`, `ScanScopePlan`, `Evidence`, `RuleMatch`, `RuleGateEvidence`, `OpenFileStatus`, `PlanCondition`, `PlanConditionKind`, `ReclaimPlan`, `ReclaimPlanItem`, `TrashExecutionSkipReason`, `ExecutionActionReceipt`, `ExecutionReceipt`, `NativeToolRisk`, `NativeToolCommand`, `NativeToolReceipt`, `NativeToolReport` → all collapse into `Finding` + `Receipt` variants, or deleted as unused in the rebuild.

### StorageAccounting.swift → Delete (replaced by one line)
Everything it does: `logicalBytes`, `allocatedBytes`, a reclaim estimate. The estimate is: `min(allocatedSize, logicalSize)`. The rest is commentary. Delete file, replace usage with `allocatedSize` directly. If you need to show "maybe you'll get X back," just display the allocated size with a note.

### DiskStatus.swift → Replace with one function (from 174 lines → ~40 lines)
`DiskStatusReader` is a class wrapping `URLResourceValues` with threshold logic. The class is instantiated once. Replace with a free function:
```swift
func diskStatus(for url: URL = URL(fileURLWithPath: "/System/Volumes/Data")) -> (free: Int64?, total: Int64?) {
    let vals = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
    return (vals?.volumeAvailableCapacityForImportantUsage, vals?.volumeTotalCapacity.map(Int64.init))
}
```
The `DiskPressureLevel` enum with thresholds → the UI can color the number green/yellow/red inline.

### BoundedFileTreeWalker.swift → Simplify (from 557 lines → ~200 lines)
**Current:** BFS with measurement layers, hard-link dedup, coverage tracking, scope metrics.  
**Simplest:** `FileManager.enumerator(at:includingPropertiesForKeys:options:)` already does recursive directory walking. The "measurement depth" concept (how deep to measure vs how deep to show) is over-engineering. Depth 2 (default) means "scan 2 levels deep." That's a simple recursion with a depth counter. Delete `FIFOFrontier`, `ScopeMetrics`, `hardLinkIdentityKeys` dedup, `measurement layers`, coverage tracking. The tree walker becomes: recurse, classify, return `[Finding]`.

### FilesystemIdentity.swift → Simplify (from 179 lines → ~30 lines)
**Current:** Full identity capture with `lstat`, hard-link keys, digest generation.  
**Simplest:** `URLResourceValues` already has `.fileResourceIdentifier` and `.volumeIdentifier`. The `lstat` call for hard-link count is only used for dedup. If you don't deduplicate, you don't need it. Drop to:
```swift
struct FileIdentity { let device: dev_t; let inode: ino_t } // 2-line struct
```

### ScopeAccessProbe.swift → Simplify (from 164 lines → ~20 lines)
**Current:** Protocol `ScopeAccessProbing` + one implementation `FileManagerScopeAccessProbe` + POSIX `opendir`/`readdir`/`closedir` for access checking + compat layer.  
**Simplest:** `FileManager.isReadableFile(atPath:)` is one call. If you need directory-specific: `FileManager.attributesOfItem(atPath:)`. Delete the whole protocol abstraction, the POSIX directory traversal, `ScopeAccessOperation` enum, `ScopeReadability` enum. The scanner already checks if a path exists/is readable via `FileManager.fileExists`.

### UserPathPolicy.swift → Simplify (from 947 lines → ~50 lines)
**Current:** 947 lines with `UserPathPolicy`, `UserPathRule`, `UserPathPolicyDocument`, `UserPathPolicyStore`, `UserPathPolicyLoadResult`, locking with `open(O_NOFOLLOW)`, POSIX stat identity checks, mutation locks, export/import, JSON encoding/decoding.  
**Simplest:** This is "a list of paths to exclude/protect." That's a `[String]` or `Set<String>` stored in `UserDefaults`. The whole secure storage machinery with POSIX directory locks for an exclusion list is absurd — the worst file I found. Delete `UserPathPolicyStore` (600+ lines), `UserPathPolicyDocument`, `UserPathPolicyImportResult`, `UserPathPolicyLoadResult`, `UserPathPolicyLoadState`, `UserPathPolicyStoreError`. Replace with:
```swift
var protectedPaths: Set<String> {
    get { Set(UserDefaults.standard.stringArray(forKey: "protectedPaths") ?? []) }
    set { UserDefaults.standard.set(Array(newValue), forKey: "protectedPaths") }
}
```

### TrashExecutionAuthorization.swift → Delete (384 lines → one function call)
**Current:** `TrashExecutionAuthorizationRegistry` (actor), `TrashExecutionAuthorization` token, `TrashExecutionReadiness` evaluation, `FileIdentityReader`, `isProtectedTrashPath`, `DryRunActionIdentity`, 10 error cases, 15-minute token expiry.  
**Simplest:** To call `FileManager.trashItem(at:)`, the user clicks "Move to Trash." That's the authorization. Delete all 384 lines. The "6-gate execution" (identity check, reclassification, open-file check, policy check, age check, timestamp check) collapses to: ask user, one `guard` for symlinks, call `trashItem`. If you really need a safety net, add one `guard` that checks `FileManager.isDeletableFile(atPath:)`.

### ActionCenter.swift → Delete (491 lines → replaced by simple UI state)
**Current:** Priority-sorted action list computed from 10+ input types.  
**Simplest:** The "action center" is the dashboard. The dashboard already shows: scan results, free space, findings. The "primary action" is whatever the user sees first. Delete the entire `ActionCenterBuilder` enum, `ActionCenterInput`, `ActionCenterReport`.

### PlanBuilder.swift → Simplify (from 403 lines → ~40 lines)
**Current:** Plan building with SHA256 stable IDs, nested selection dedup, 6 kinds of gate evaluation, canonical encoding.  
**Simplest:** A plan is: `selectedFindings: [Finding]`. No plan ID, no canonical encoding, no SHA256. The user selects items in the UI → that's the plan. Gate evaluation → if `safetyClass == .autoSafe` and not a symlink, selectable. Done.

### ReclaimerExecutor.swift → Simplify (from 822 lines → ~100 lines)
**Current:** `executeAuthorizedTrash` with identity recheck, reclassification, open-file recheck, policy recheck, age recheck, path containment check, atomic identity comparison, user path policy loading mid-execution.  
**Simplest:** `FileManager.trashItem(at:)` wrapped in a `do/catch`. If you want a safety check: re-verify the path still exists and is not a symlink before trashing. That's two `guard` statements.

### NativeToolExecution.swift → Delete (542 lines → gone)
**Current:** Homebrew-preview-specific executor with SHA256 authorization digests, `NativeToolPerformAuthorization`, `isExactHomebrewPreviewInvocation`, `isExactHomebrewCleanupInvocation`, 15-minute preview expiry.  
**Simplest:** The rebuild plan has no "native tool execution via Ryddi." The guidance is "run `brew cleanup` yourself." Delete entire file.

### NativeActionReceipt.swift → Delete (577 lines → gone)
**Current:** Another homebrew execution path with `NativeActionExecutor`, `NativeHomebrewCleanupCapability`, `NativeHomebrewCleanupPreview`, UUID capability tokens, executor-minted capabilities.  
**Simplest:** Same as above. Delete.

### FindingAnalytics.swift → Simplify (from 1785 lines → ~50 lines)
**Current:** Bucket summaries, scope access summaries, finding analytics, review queue building, disk overview.  
**Simplest:** The UI needs: total reclaimable bytes, top N largest findings, grouped by category. That's a `reduce` + `sorted` + `prefix`. All the analytics structs (`BucketSummary`, `ScopeAccessSummary`, `ScanOverview`, `ScanDiskBreakdown`, `DiskPressureDashboard`) are UI view-models. They should live in the UI layer, not in ReclaimerCore. Collapse to one function: `summarize(findings: [Finding]) -> Summary`.

### CleanupGuidance.swift → Simplify (from 329 lines → ~40 lines)
**Current:** Maps path patterns to CLI command suggestions.  
**Simplest:** A dictionary: `["/.colima": "colima list && docker system df", ...]`. Done.

### 28 Dashboard model extensions → Collapse into DashboardModel.swift
`DashboardModel+AuditAndRecovery`, `+Exports`, `+Remote`, `+Reviews`, `+ScanPlan` — these are all just methods on `DashboardModel`. Merge them or delete unused methods.

### CLI files (reclaimer/ target) → Simplify (from ~3,200 lines → ~100 lines)
`ReclaimerCLI.swift` (2256 lines), `ReviewCommands.swift` (1800 lines), `RemoteCommands.swift` (511 lines), `AuditCommands.swift`, `ReportCommands.swift`, `IssueCommands.swift`, `CLIOptions.swift`.  
**Simplest:** The rebuild has a CLI for "scan and report." That's: `reclaimer scan --scope developer` → print JSON. Delete the other 6 command files. The CLI should be ~100 lines using `ArgumentParser`.

### All Review scanner files → Collapse into one `UnifiedReviewScanner`
`TrashReview.swift` (317 lines) — reviews ~/.Trash.  
`ArchiveReview.swift` (502 lines) — reviews ~/Library archives.  
`AgentStorageReview.swift` (804 lines) — reviews AI agent dirs.  
`AppReview.swift` (635 lines) — reviews /Applications.  
`BrowserCacheReview.swift` (834 lines) — reviews browser caches.  
`DeviceBackupReview.swift` (651 lines) — reviews iOS backups.  
`DownloadsReview.swift` (816 lines) — reviews ~/Downloads.  
`DuplicateReview.swift` (477 lines) — finds duplicates.  
`ProjectDependencyReview.swift` (3028 lines — worst offender) — reviews project deps.  
`XcodeReview.swift` (749 lines) — reviews Xcode caches.  
`PackageCacheReview.swift` (625 lines) — reviews package caches.  
`ActiveFileReview.swift` (179 lines) — checks open files.  

All of these are the same pattern: scan directory X, apply rules, return `[Finding]`. The `FileScanner` already does this generically. The only difference is the directory path. Delete all 12 specialized review files. `TrashReview` is `FileScanner().scan(scopes: [ScanScope(name: "Trash", root: .trash)])`.

### GuidedMap files → Delete (5 files, ~480 lines)
`GuidedMap.swift`, `GuidedMapStore.swift`, `GuidedMapBreadcrumbView.swift`, `GuidedMapInspectorView.swift`, `GuidedMapOutlineView.swift`, `GuidedTreemapView.swift`, `TreemapLayout.swift`.  
**Ponytail verdict:** A treemap visualization of disk usage is a nice-to-have. For the rebuild, `du -sh * | sort -h` provides the same information. Delete all 7 files. The rebuild has 3 pillars, none of which need a treemap.

### Dashboard UI → Collapse from 30+ files to ~5
UI files that are just view factories or single-purpose views:
- `DashboardContentViews.swift` (4225 lines — split into components)
- `DashboardDemoData.swift` (639 lines — demo/test data, delete)
- `DashboardDependencies.swift` (91 lines — dependency container, delete use `@Environment`)
- `DashboardActivity.swift` (128 lines — activity indicators)
- `DashboardCommands.swift` (50 lines — command definitions)
- `DashboardSettingsView.swift` (134 lines — settings)
- `DashboardSidebarView.swift` (25 lines — sidebar)
- `DashboardView.swift` (130 lines — main layout)
- `DeveloperStorageReviewViews.swift` (1432 lines — developer-specific views)
- `AppReviewViews.swift` (741 lines — app review views)
- `SharedFindingRows.swift` — shared row views
- `PathActions.swift` — path action buttons
- `FindingDetailView.swift` — detail view
- `LargeOldReviewView.swift` — large/old file review
- `ReviewQueuesView.swift` (806 lines) — review queues
- `CloudStorageWorkspaceView.swift` (744 lines) — cloud workspace
- `GuidedSummaryView.swift` (570 lines) — guided summary
- `RemoteTargetsView.swift` — remote targets view
- `AuditHistoryView.swift` — audit history
- `TrashConfirmationView.swift` — trash confirmation
- `PermissionOnboardingView.swift` — permission onboarding
- `StatusMenuView.swift` — status bar menu
- `RyddiWindowLayout.swift` — window layout
- `ResponsiveLayout.swift` (13 lines) — responsive layout trait
- `Explore/ExploreView.swift` — explore view
- `Explore/ExploreFilter.swift` — explore filter
- `Home/` (5 files, ~400 lines) — home screen
- `History/HistoryView.swift` — history view

**Ponytail verdict:** The rebuild has Clean, Offload, Control — 3 views, not 28 sidebar sections. Collapse all UI into `MainView.swift`, `CleanView.swift`, `OffloadView.swift`, `ControlView.swift`. Delete `DashboardDemoData`, `CloudStorageWorkspaceView`, `RemoteTargetsView`, `GuidedSummaryView`, `ExploreView`, `HistoryView`, `ReviewQueuesView`, all specialized review views.

---

## RUNG 7: KEEP — Minimum code that works

These are the files that survive in some form in the rebuild:

| File | What becomes of it |
|------|-------------------|
| `Models.swift` | Collapsed to ~100 lines (Finding, SafetyClass, ActionKind, PermissionState, ScanScope) |
| `Rules.swift` | RuleEngine (~50 lines — classify path by pattern) |
| `Scanner.swift` | FileScanner (~100 lines — walk dirs, classify, return Findings) |
| `ReclaimerExecutor.swift` | Collapsed to ~30 lines (trashItem wrapper) |
| `BoundedFileTreeWalker.swift` | Simplified recursion (~80 lines) |
| `DiskStatus.swift` | Free function (~15 lines) |
| `FilesystemIdentity.swift` | 2-line struct (device, inode) |
| `UserPathPolicy.swift` | UserDefaults wrapper (~15 lines) |
| `ScanControl.swift` | Tiny (cancellation + progress) |
| `TrashReview.swift` | Merged into Scanner (Trash is just a directory) |
| `SafeFileOutput.swift` | Atomic file write (~30 lines — keep, useful utility) |
| `ByteFormat` | Delete — use `ByteCountFormatter` directly |
| `RuleCatalog.swift` | Delete — rules.json loaded by RuleEngine |
| `ScopeTemplate.swift` | Merge into Scanner |
| `SavedScopeSet.swift` | Merge into UserDefaults |
| `Schedule...` | Replaced by launchd plist |
| `MacDiskReclaimerApp.swift` | Keep — app entry point |
| `DashboardModel.swift` | Collapse to ~30 properties |
| `RyddiAppModel.swift` | Keep — NSApplication delegate |
| `RyddiUpdateController.swift` | Keep — Sparkle/SUS |
| `RyddiLog.swift` | Keep — logging |
| `AccessibilityIDs.swift` | Keep |

---

## Quantified Savings

| Metric | Current | After Ponytail | Reduction |
|--------|---------|---------------|-----------|
| **Files** | 167 | ~20 | **-88%** |
| **Lines** | 64,153 | ~1,200 | **-98%** |
| **Targets** | 5 | 2 (App + CLI) | **-60%** |

### Top 5 Worst Offenders (lines vs. value)

| File | Lines | What it does | Real value |
|------|-------|-------------|------------|
| `DashboardContentViews.swift` | 4,225 | 28 sidebar sections of SwiftUI views | 3-screen app needs ~200 lines |
| `ProjectDependencyReview.swift` | 3,028 | Scans project deps | Already covered by FileScanner |
| `ReclaimerCLI.swift` | 2,256 | CLI with 7 subcommands | `scan` is one command |
| `FindingAnalytics.swift` | 1,785 | Analytics on findings | `reduce` + `sorted` = 20 lines |
| `ReviewCommands.swift` | 1,800 | Review subcommands for CLI | Merged into scan |

### Bottom 5 (files that should never have existed)

| File | Lines | Why |
|------|-------|-----|
| `ResponsiveLayout.swift` | 13 | `@Environment(\.horizontalSizeClass)` is built-in |
| `MarkdownTable.swift` | 11 | A one-line `map` + `joined` |
| `AccessibilityIDs.swift` | 36 | `.accessibilityIdentifier()` is per-view |
| `DashboardSidebarView.swift` | 25 | SwiftUI sidebar is 3 lines |
| `RyddiWindowLayout.swift` | 19 | `WindowGroup` + `.defaultSize` is built-in |

---

## Ponytail Ladder Applied

**Rung 1 (Delete):** 62 files → RyddiProtectCore, RyddiProtectAuth, all remote scanning, all specialized review scanners, all report/export files, GuidedMap, ActionCenter, scheduling, permission machinery, cloud features  
**Rung 2 (Reuse):** 0 files — nothing already in stdlib got reimplemented (well, except `ByteCountFormatter` and `JSONEncoder`)  
**Rung 3 (Stdlib):** `ByteFormat` → `ByteCountFormatter`, `FileIdentityReader` → `lstat`, `ScopeAccessProbe` → `FileManager.isReadableFile`, `SafeFileOutput` → `Data.write(to:options:)` with `.atomic`  
**Rung 4 (Native):** `Scheduler` → `launchd`, `ResponsiveLayout` → `horizontalSizeClass`, `DiskStatusReader` → `URLResourceValues`  
**Rung 5 (Installed dep):** N/A — no deps used for what stdlib covers  
**Rung 6 (One line):** 38 individual file functions that are one-liners (e.g., `TrashReview`, `DockerVolumeRemoval`, `ColimaProfileInventory`, `CleanupGuidance`, every "Guidance" file)  
**Rung 7 (Minimum code):** 20 surviving files at ~1,200 total lines

---

## Recommended Execution Order

1. **Delete RyddiProtectCore + RyddiProtectAuth** (15 files, no consumers)
2. **Delete all remote scanning files** (7 files)
3. **Delete all specialized review scanners** (12 files, replace with Scanner)
4. **Delete all report/export files** (14 files)
5. **Delete GuidedMap + treemap** (7 files)
6. **Delete ActionCenter, PlanBuilder complexity** (2 files)
7. **Simplify Models.swift** (drop manual Codable, ByteFormat, evidence types)
8. **Simplify UserPathPolicy** (947 → 15 lines)
9. **Simplify BoundedFileTreeWalker** (557 → 80 lines)
10. **Delete TrashExecutionAuthorization** (384 lines → direct call)
11. **Collapse Dashboard UI** (30 → 5 files)
12. **Simplify CLI** (3200 → 100 lines)
