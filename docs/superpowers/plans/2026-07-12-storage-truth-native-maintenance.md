# Storage Truth And Native Maintenance Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans) to implement this plan task-by-task.

**Goal:** Ship the approved B+C slice for Ryddi v0.3: make local storage findings honest about logical versus allocated versus observed reclaim, make broad scans bounded and explicit about coverage, recognize shared Chrome clone groups without false open-file blocks, add conservative Codex/npm/Docker cache rules, and execute only two narrowly allowlisted native maintenance actions through fresh same-process previews and receipts.

**Architecture:** Keep `ReclaimerCore` as the source of truth for scanner accounting, filesystem identity, rule classification, native action capabilities, receipts, and audit evidence. Keep the CLI and SwiftUI app as adapters over those core models. Native execution remains local-only, user-confirmed, preview-gated, and never available to the report-only scheduler/agent. Raw VM disks, Docker volumes/containers/images, browser profiles, Codex sessions/memories/config/auth, project dependencies, credentials, and unknown state remain preserve/review-only.

**Tech Stack:** Swift 6, SwiftPM, macOS 14+, Foundation URL resource values, `/usr/bin/env` tool execution, existing `DiskStatusReader`, `ToolCommandRunning`, `NativeActionExecutor`, `AuditStore`, SwiftUI, XCTest, bounded `.build` scratch path.

---

## Global Guardrails

- Run `df -h /System/Volumes/Data` before every long test/build loop; stop and report if free space is below `50Gi`.
- Use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"` only. Do not create unbounded scratch directories under `/private/tmp`.
- Preserve backwards decoding for all persisted `Finding`, `FilesystemIdentity`, `OpenFileStatus`, `NativeToolExecutionReceipt`, and audit records.
- Do not add a root helper, Full Disk Access auto-grant, process termination, remote cleanup, telemetry, automatic native maintenance, scheduled destructive work, or raw deletion of VM/container/browser/Codex state.
- Every native perform action must be issued by the same `NativeActionExecutor` instance that performed the successful preview. Codable receipts and printed digests are evidence, never capabilities.
- Every result must distinguish estimates from observed `df` deltas and carry explicit non-claims when APFS, snapshots, clones, sparse files, or tool accounting can differ.
- Follow TDD for each task: add a focused failing test, run its narrow filter and observe failure, implement the smallest change, rerun the narrow filter and full relevant suite, then commit the task slice.
- After each implementation task, use two review passes before starting the next task: first spec-compliance review, then code-quality/regression review. Resolve findings and rerun tests after each pass.

## Task 1: Persist Plan And Establish Baseline

**Files:**
- Create: `docs/superpowers/plans/2026-07-12-storage-truth-native-maintenance.md`
- No production code changes.

- [ ] Confirm the worktree is on `feature/v0.3-trust-to-action` and clean except for the new plan.
- [ ] Run `df -h /System/Volumes/Data`; stop if the available column is below `50Gi`.
- [ ] Run `swift test --scratch-path "$PWD/.build"` and record the baseline result without changing test behavior.
- [ ] Commit the plan as `docs: add storage truth and native maintenance plan`.
- [ ] Review the commit diff and verify the plan names concrete files, tests, safety gates, and verification commands.

## Task 2: Add Storage Accounting And Hard-Link Identity Primitives

**Files:**
- Create: `Sources/ReclaimerCore/StorageAccounting.swift`
- Modify: `Sources/ReclaimerCore/Models.swift`
- Modify: `Sources/ReclaimerCore/FilesystemIdentity.swift`
- Modify: `Sources/ReclaimerCore/NativeActionReceipt.swift`
- Modify: `Tests/ReclaimerCoreTests/StorageAccountingTests.swift`

**Interfaces:**
- Add `StoragePhysicalReclaimStatus: String, Codable, Hashable, Sendable` with `unknown`, `estimated`, `sharedCloneBacked`, and `observedDelta`.
- Add `StorageAccounting: Codable, Hashable, Sendable` with `logicalBytes`, `allocatedBytes`, `physicalReclaimStatus`, optional `physicalReclaimBytes`, `deduplicationNote`, and a stable `estimatedImmediateReclaimBytes` accessor.
- Add optional `storageAccounting` and optional `measurementCoverage` fields to `Finding`, decoding absent fields as a synthesized estimate from legacy logical/allocated values.
- Add `hardLinkCount: Int?` and `fileIdentityKey: String?` to `FilesystemIdentity`, preserving old JSON decoding and digest behavior for records without the fields.
- Add optional `beforeObservedFreeBytes`, `afterObservedFreeBytes`, and `observedReclaimBytes` to native receipts; never replace existing before/after fields.

- [ ] Write tests for equal logical/allocated sizes, sparse/compressed-style allocated estimates, unknown accounting, observed `df` delta, and conservative negative/zero delta handling.
- [ ] Write tests that two hard-linked regular files have the same identity key and that a directory or symlink does not acquire a misleading hard-link identity.
- [ ] Write tests that legacy Finding, FilesystemIdentity, and NativeActionReceipt JSON decode with nil new fields and stable existing values.
- [ ] Implement the new types and backward-compatible custom decoding where synthesized values are required.
- [ ] Update `Finding.storageAccountingNote` to report estimate/observation language and avoid promising reclaim from allocated size alone.
- [ ] Update native receipt construction to record observed free-space deltas only after a successful perform command; dry runs must leave observed reclaim nil.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter StorageAccounting` and then the full core test suite.
- [ ] Commit as `feat: add honest storage accounting primitives`.

## Task 3: Make Open-File Checks Clone-Aware And Fail Closed

**Files:**
- Create: `Sources/ReclaimerCore/FilesystemLinkInspector.swift`
- Modify: `Sources/ReclaimerCore/FilesystemIdentity.swift`
- Modify: `Sources/ReclaimerCore/OpenFileChecker.swift`
- Modify: `Sources/ReclaimerCore/PlanBuilder.swift`
- Modify: `Sources/ReclaimerCore/ReclaimerExecutor.swift`
- Modify: `Tests/ReclaimerCoreTests/CloneAwareOpenFileTests.swift`
- Modify: `Tests/ReclaimerCoreTests/ExecutorFinalGateRevalidationTests.swift`

**Interfaces:**
- Add a local `FilesystemLinkObservation` value with normalized path, volume/file identity, regular-file state, link count, and preservation evidence.
- Add `OpenFileIdentityHit` and `OpenFileCheckEvidence` to distinguish ordinary open paths, recursive descendant hits, shared hard-link identities, and failed identity resolution.
- Keep `OpenFileStatus` Codable/API-compatible while adding optional clone-aware evidence fields and a displayable reason.
- Add a `CloneGroupPolicy` decision helper that can return `blocked`, `sharedOpenIdentityOnly`, or `clear`; ordinary files/directories remain blocked when identity or preservation proof is incomplete.

- [ ] Add a fixture test creating one regular file and two hard links, with fake lsof output pointing at one link; prove an ordinary sibling is not marked open solely because the shared executable is open.
- [ ] Add tests proving a unique open descendant, missing preserved sibling, symlink, changed file identity, changed link count, or failed lstat/resource read blocks the parent action.
- [ ] Add tests for hard-linked file accounting so a scan counts the physical identity once while still displaying every path as review evidence.
- [ ] Implement identity collection using Foundation resource values plus Darwin `stat` data where available; treat unsupported/missing link metadata as unknown and fail closed.
- [ ] Keep recursive directory checks for directories and carry `checkedRecursively`/`checkedPath` through existing status output.
- [ ] Update final executor revalidation to re-read metadata, user policy, symbolic-link status, classification, identity/link evidence, and recursive open status immediately before every perform action.
- [ ] Add receipt messages distinguishing `shared open identity preserved` from `recursive open-file check blocked action`.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter CloneAwareOpenFile`, `--filter ExecutorFinalGate`, and the full suite.
- [ ] Commit as `fix: make clone-aware open-file checks fail closed`.

## Task 4: Add Bounded Scan Budgets And Coverage Evidence

**Files:**
- Create: `Sources/ReclaimerCore/ScanCoverage.swift`
- Modify: `Sources/ReclaimerCore/Scanner.swift`
- Modify: `Sources/ReclaimerCore/ScanSession.swift`
- Modify: `Sources/ReclaimerCore/Overview.swift`
- Modify: `Sources/reclaimer/ReclaimerCLI.swift`
- Modify: `Tests/ReclaimerCoreTests/BoundedScanTests.swift`

**Interfaces:**
- Add `ScanCoverageState: String, Codable, CaseIterable, Hashable, Sendable` with `complete`, `bounded`, and `degraded`.
- Add `ScanCoverage: Codable, Hashable, Sendable` with requested item budget, measured item count, skipped item count, roots visited, roots denied, maximum depth, and evidence messages.
- Extend scan results without breaking `[Finding]` callers by adding `ScanResult { findings, coverage }` and a compatibility `scan(...) -> [Finding]` wrapper or an equivalent session result.
- Extend `ScanOptions` with `measurementItemBudget`, `deduplicateHardLinks`, and an explicit broad-scan measurement depth default; clamp all values to safe finite bounds.
- Add CLI flags `--measurement-budget N`, `--measurement-depth N`, and `--deduplicate-hardlinks`; include coverage in JSON and table output.

- [ ] Write a synthetic-tree test where a low measurement budget yields `bounded`, stable skipped counts, and partial findings rather than hanging or silently reporting complete coverage.
- [ ] Write a test proving symlinks are not followed and hard-linked identities are measured once when deduplication is enabled.
- [ ] Write a regression test showing broad scans do not recursively remeasure every parent and child to the same full depth; measured item work must be bounded by the configured budget.
- [ ] Write tests for permission-denied and missing roots producing `degraded` coverage with explicit root evidence.
- [ ] Implement one bounded traversal/measurement context shared by a scan instead of an unbounded recursive measurement per finding. Preserve rule matching and top-level finding behavior.
- [ ] Keep exact small targeted scans capable of `complete` coverage; broad developer/general presets should use bounded defaults and surface the state.
- [ ] Mark estimates from bounded measurements as estimated and prevent them from becoming destructive-plan authorization without a fresh targeted scan.
- [ ] Update `ScanSession` and overview summaries to show `Complete`, `Bounded`, or `Degraded` and a targeted-rescan affordance.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter BoundedScan`, CLI fixture smoke, then the full suite.
- [ ] Commit as `feat: add bounded scan coverage evidence`.

## Task 5: Add Conservative Chrome, Codex, Docker, npm, And Named-Cache Rules

**Files:**
- Modify: `Sources/ReclaimerCore/Rules.swift`
- Modify: `Sources/ReclaimerCore/Resources/rules.json`
- Modify: `Sources/ReclaimerCore/CleanupGuidance.swift`
- Modify: `Sources/ReclaimerCore/Scanner.swift`
- Modify: `Tests/ReclaimerCoreTests/StorageRulePackTests.swift`

- [ ] Add rule fixtures for `X/com.google.Chrome.code_sign_clone`, proving active/shared clone groups remain review or safe-after-condition and are never independent auto-safe deletion candidates.
- [ ] Add Codex log rules with typed `openFileClear`, `minimumAgeRequired`, and `finalClassificationRequired` gates; current-day and open logs remain protected/review-only. Keep sessions, archived sessions, memories, auth, config, and state protected.
- [ ] Add/adjust the rebuildable Codex cache rule so only explicitly cache/tmp leaves with open-file gates can be auto-safe; broad `.codex` roots never inherit cleanup safety.
- [ ] Add Docker/Colima build-cache classification that points to native Docker inspection/prune guidance without classifying `.colima`, `docker.raw`, VM files, volumes, images, or containers as raw-delete candidates.
- [ ] Separate npm cache and npx sandboxes from `node_modules`, lockfiles, project directories, configs, and credentials; mark active npx state as protected or quit/review.
- [ ] Add a named Stremio cache-leaf rule and ensure its parent app state remains preserve-by-default.
- [ ] Verify condition text is never authoritative: typed gates and final classification decide selection, and all stale/manual/native/current-day conditions fail closed.
- [ ] Update native guidance IDs to include `docker.builder-prune` and `npm.cache-clean` while retaining existing destructive Docker/package commands as guidance-only blocked actions.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter StorageRulePack`, plan builder filters, and full tests.
- [ ] Commit as `feat: expand conservative developer cache rules`.

## Task 6: Generalize Native Preview/Perform To Docker Build Cache And npm Cache

**Files:**
- Create: `Sources/ReclaimerCore/NativeMaintenance.swift`
- Modify: `Sources/ReclaimerCore/SafeActionPlanner.swift`
- Modify: `Sources/ReclaimerCore/NativeActionReceipt.swift`
- Modify: `Sources/ReclaimerCore/NativeToolExecution.swift`
- Modify: `Sources/ReclaimerCore/ContainerInventory.swift`
- Modify: `Sources/ReclaimerCore/CleanupGuidance.swift`
- Modify: `Tests/ReclaimerCoreTests/NativeMaintenanceTests.swift`
- Modify: `Tests/ReclaimerCoreTests/NativeActionAllowlistTests.swift`
- Modify: `Tests/ReclaimerCoreTests/NativeActionReceiptTests.swift`

**Interfaces:**
- Add `NativeMaintenanceAction: String, Codable, Hashable, Sendable` with `dockerBuilderPrune` and `npmCacheClean`.
- Add an internal capability-bearing `NativeMaintenancePreview` that carries a successful preview receipt and a non-Codable executor-minted token. Do not make the token or capability Codable/publicly forgeable.
- Add exact argv constructors:
  - Docker preview/perform: `docker builder prune --force --dry-run` is not a universally supported Docker command, so use read-only `docker system df -v` as the preview evidence and perform only exact `docker builder prune --force` after an explicit same-process confirmation. The command ID must bind the active Docker context and preview digest.
  - npm preview/perform: `npm cache verify` as preview and exact `npm cache clean --force` as perform, with no path/extra argument injection.
- Add action-specific receipts with tool identity, command argv, preview digest, before/after disk status, stdout/stderr previews, and `observedReclaimBytes` only when measured.

- [ ] Write allowlist tests proving exact Docker builder prune and npm cache clean argv are allowed only for their matching action; reject `docker system prune`, `docker volume prune`, `docker system prune --volumes`, `docker builder prune --all`, reset/VM commands, arbitrary npm arguments, shell wrappers, and executable substitution.
- [ ] Write tests proving a preview from one executor, context, finding path, rule version, or command digest cannot authorize a perform on another; capability reuse and stale capability are rejected.
- [ ] Write fake-runner tests for successful preview, explicit confirmation, perform, output capture, failure, timeout, and before/after disk delta.
- [ ] Add safe action kinds and planner candidates only for these two actions; keep them review/native-gated and never auto-run by the scheduler.
- [ ] Implement native inspection context binding: Docker context from `docker context show`/inventory and npm executable identity/version from `npm --version` or exact tool path; no sudo and no root helper.
- [ ] Keep current Homebrew same-process capability behavior intact and share only safe receipt helpers where the existing tests prove compatibility.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter NativeMaintenance`, `--filter NativeAction`, then full suite.
- [ ] Commit as `feat: add preview-gated Docker and npm maintenance`.

## Task 7: Wire CLI Native Actions, Coverage, And Audit Evidence

**Files:**
- Modify: `Sources/reclaimer/ReclaimerCLI.swift`
- Modify: `Sources/reclaimer/RemoteCommands.swift` only if shared printing needs extraction; do not alter remote safety behavior.
- Modify: `Sources/ReclaimerCore/AuditStore.swift`
- Modify: `Sources/ReclaimerCore/ReceiptReportExport.swift`
- Modify: `Tests/ReclaimerCoreTests/NativeCLITests.swift`
- Modify: `Tests/ReclaimerCoreTests/AuditStoreHygieneTests.swift`

- [ ] Add `--measurement-budget`, `--measurement-depth`, and `--deduplicate-hardlinks` to all local scan/report commands that construct `ScanOptions`.
- [ ] Print coverage state and separate logical bytes, allocated estimates, and observed reclaim in overview, native, plan, receipt, and JSON output without breaking existing JSON keys.
- [ ] Extend `reclaimer native run --command-id docker.builder-prune|npm.cache-clean --dry-run|--yes` so `--yes` performs the in-process preview then confirmation path, while a saved receipt alone remains insufficient.
- [ ] Reject native commands whose finding is protected, active, clone-ambiguous, bounded-only, stale, or lacks required native inventory evidence.
- [ ] Save preview and perform receipts through the existing audit store with known prefixes; include command digest and non-claims.
- [ ] Add CLI tests that no native command path can launch Docker system/volume prune, Colima delete/reset, VM deletion, arbitrary npm arguments, or a shell wrapper.
- [ ] Add smoke tests with fake runners through `ReclaimerCLI.run(arguments:)` where the current CLI dependency seam permits; otherwise test the core command builder and receipt formatter directly.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter NativeCLI`, `swift run --scratch-path .build reclaimer overview --preset developer --measurement-budget 1000 --json`, and full tests.
- [ ] Commit as `feat: expose bounded evidence and native maintenance in cli`.

## Task 8: Make SwiftUI Show Storage Truth And Action Boundaries

**Files:**
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- Modify: `Sources/MacDiskReclaimerApp/GuidedSummaryView.swift`
- Modify: `Sources/MacDiskReclaimerApp/AuditHistoryView.swift`
- Modify: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`
- Modify: `Tests/ReclaimerCoreTests/AppE2EFixtureTests.swift`

- [ ] Add overview cards for coverage state, measured/skipped items, logical size, allocated estimate, observed reclaim, and a clear “estimate, not a promise” explanation.
- [ ] Add clone-group detail copy explaining shared executable identity and preserved links; do not show each clone sibling as independently reclaimable.
- [ ] Add native action cards showing owner/tool, active context, exact preview command, expected effect, current status, last receipt, and a single explicit confirmation affordance.
- [ ] Keep Docker VM/volumes/images/containers and Codex sessions/memories/auth/config visibly preserve/review-only; ensure no “Reclaim” button appears for those rows.
- [ ] Add targeted rescan action when a bounded result is selected for native maintenance; require the targeted result to be complete enough before enabling confirmation.
- [ ] Keep automation UI copy/report path explicitly report-only and prevent native perform controls from appearing in scheduled/agent views.
- [ ] Test compact, minimum, and wide window layouts; verify long paths, localized byte strings, badges, table columns, and native command previews do not overlap or force unusable horizontal clipping.
- [ ] Run the app layout/E2E fixture tests and `swift build --scratch-path "$PWD/.build"`; manually open the installed/debug app and exercise Summary, Review Queues, Apps & Leftovers, Native guidance, and Audit History.
- [ ] Commit as `feat: surface storage truth and native action boundaries in app`.

## Task 9: End-To-End Fixture Proof And Documentation

**Files:**
- Create: `Tests/ReclaimerCoreTests/StorageTruthE2ETests.swift`
- Create: `Scripts/storage-truth-smoke.sh`
- Modify: `Scripts/release-check.sh`
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `PRIVACY.md`
- Modify: `docs/RELEASE_CHECKLIST.md`
- Modify: `docs/REMOTE_TARGETS.md` only if shared non-claims need correction; remote v1 remains read-only.

- [ ] Build a disposable fixture tree containing hard links, a symlink, Codex current/recent/old logs, sessions/memories/auth, Chrome clone-like paths, npm cache/npx, Docker/Colima names, project dependencies, and a named application cache.
- [ ] Run a bounded scan against the fixture and assert stable JSON contains coverage, accounting statuses, protection classes, clone evidence, and no raw-delete candidates for protected buckets.
- [ ] Run native guidance generation and assert exact safe action IDs plus blocked dangerous IDs; use fake runners only, never the live Docker daemon or npm cache.
- [ ] Run preview/perform core tests against fake Docker/npm runners and assert receipts include before/after disk snapshots and honest observed/unverified status.
- [ ] Assert the fixture test never mutates protected files, never follows symlinks, never launches shell commands, and leaves the scheduler/agent report-only.
- [ ] Add a bounded shell smoke script using a run-local `mktemp -d` and `trap 'rm -rf "$scratch"' EXIT`; do not write to `/private/tmp` without cleanup.
- [ ] Update docs to explain clone/shared allocation limits, bounded coverage, native preview/perform rules, exact commands, no root/sudo, no VM or Codex history deletion, and observed `df` delta semantics.
- [ ] Run `bash -n Scripts/storage-truth-smoke.sh Scripts/release-check.sh Scripts/package-app.sh Scripts/notarize-app.sh`.
- [ ] Commit as `test: add storage truth and native maintenance evidence`.

## Task 10: Final Verification, Review, And Release Readiness

- [ ] Run `df -h /System/Volumes/Data`; stop if free space is below `50Gi`.
- [ ] Run focused tests for storage accounting, clone-aware open files, bounded scans, rule packs, native maintenance, CLI, layout, and E2E fixtures.
- [ ] Run `swift test --scratch-path "$PWD/.build"`.
- [ ] Run `swift build --scratch-path "$PWD/.build"`.
- [ ] Run `Scripts/storage-truth-smoke.sh` and `Scripts/release-check.sh` with no signing/notarization claims unless Developer ID and notarization proof is present.
- [ ] Run `git diff --check` and inspect `git status --short` for generated artifacts or unbounded scratch output.
- [ ] Run a final spec-compliance review against the design spec, then a final regression/security review. Resolve every finding or document an explicit non-goal.
- [ ] Verify `git log` contains small task commits and no secrets, private key material, or real path dumps in docs/tests.
- [ ] Log evidence to Obsidian daily note and `Personal/Projects/Mac Disk Reclaimer.md`, including commit SHAs, tests, coverage/native safety boundaries, and any remaining release blockers.
- [ ] Do not publish a release or claim signing/notarization; Apple Developer ID state is independent of this slice and must be proven separately.

## Acceptance Criteria

- A broad scan reports whether coverage is complete, bounded, or degraded and never presents a bounded estimate as an exact reclaim promise.
- Logical size, allocated estimate, shared clone/hard-link state, and observed disk delta are visibly distinct in JSON, CLI, receipts, and app UI.
- A shared hard-linked Chrome executable does not falsely block every sibling, while ordinary ambiguous paths and unique open descendants remain fail-closed.
- Codex sessions/memories/config/auth, Chrome profiles, Colima/VM disks, Docker volumes/containers/images, project dependencies, credentials, and unknown app state are preserved or review-only.
- Only exact local `docker builder prune --force` and `npm cache clean --force` actions can reach the new preview-gated native path; dangerous variants and shell wrappers are rejected before launch.
- Native actions require a successful same-process preview, explicit user confirmation, fresh final validation, and a receipt with command/context evidence and observed-delta non-claims.
- Scheduler and agent remain report-only; no native perform path is exposed to unattended automation.
- Full tests, build, fixture E2E, release checks, and `git diff --check` pass with disk headroom above `50Gi`.
