# Ryddi Guided Map Regular-User Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with test-first changes and a review checkpoint after every task. If the user explicitly chooses delegated execution, use isolated subagents per task; otherwise execute inline in the listed order.

**Goal:** Replace Ryddi's feature-dense dashboard with a user-started, treemap-led Home, explicit cleanup review, focused Explore, and trustworthy History experience for regular Mac users without weakening core cleanup authority.

**Architecture:** `ReclaimerCore` remains the sole source of scan, classification, plan, dry-run, and execution authority. Add pure presentation builders for the map, Home, and selection boundary; persist only display-safe map snapshots; render those models through three SwiftUI destinations. The visual map may explain evidence, but it never selects or deletes anything.

**Tech stack:** Swift 6, SwiftUI, Observation, Swift Package Manager, XCTest, macOS 14+, the existing packaged-app Accessibility harness, and the current shell release gates.

**Approved design:** `docs/superpowers/specs/2026-07-17-ryddi-guided-map-regular-user-design.md`

## Global Constraints

- [ ] Begin from an isolated worktree and branch named `codex/guided-map-v0.4`; do not implement this work directly on the open Protect branch or mix it into PR #8.
- [ ] Start only after the Protect baseline and approved design commit are reachable from the chosen base. If they are not on `origin/main`, cherry-pick only the required documentation commit before implementation.
- [ ] Before long build or test loops, run `df -h /System/Volumes/Data` and stop if free space is below 30 GiB.
- [ ] Use `swift test --scratch-path "$PWD/.build"`, `swift build --scratch-path "$PWD/.build"`, and `xcodebuild ... -derivedDataPath "$PWD/.derivedData"` where applicable.
- [ ] Preserve user-started scanning. Opening or restoring the app must not start a heavy scan.
- [ ] Preserve the latest trustworthy completed map when a refresh is cancelled, fails, or returns a stale request.
- [ ] Start every cleanup review with no selected findings. A visual map selection is never a cleanup selection.
- [ ] Keep allocated bytes, conservative estimated reclaim, and observed reclaimed bytes separate in models, copy, and accessibility labels.
- [ ] Keep existing safety gates: protected paths, typed classification, recursive-target rejection, link checks, current filesystem identity, open-handle checks, dry run, one-use authorization, Trash-first execution, receipts, and verification.
- [ ] Do not add direct delete, direct Trash, or add-to-plan actions to the treemap or outline.
- [ ] Do not add telemetry, cloud upload, root helpers, remote cleanup, or inferred ownership.
- [ ] Treat accessibility and the keyboard outline as product behavior, not a later polish pass.
- [ ] Treat `~/.codex/config.toml` and secret-bearing environment files as read-only.
- [ ] Commit each task separately after its focused tests pass and `git diff --check` is clean.

## Relationship To Existing v0.4 Work

This plan supersedes Tasks 1-6 and the app-journey portion of Task 8 in `docs/superpowers/plans/2026-07-14-ryddi-v0.4-guided-cleanup-and-e2e.md`. Its Remote Targets batching and release-proof work remain separate follow-on work. Do not silently combine those scopes with the Guided Map implementation.

## Task 1: Add The Core Guided Map Presentation Model

**Files**

- Create: `Sources/ReclaimerCore/GuidedMap.swift`
- Create: `Tests/ReclaimerCoreTests/GuidedMapTests.swift`
- Modify: `Sources/ReclaimerCore/ScanPresentationSnapshot.swift`
- Read and reuse: `Sources/ReclaimerCore/DiskDrillDown.swift`

### Contract

Add these public, `Sendable`, `Codable`, and `Equatable` presentation types:

```swift
public enum GuidedMapCategory: String, Codable, Sendable, CaseIterable {
    case applications, personalFiles, developerFiles, media
    case caches, system, otherMeasured, limitedVisibility
}

public enum GuidedMapMeasurementState: String, Codable, Sendable {
    case complete, bounded, limited
}

public enum GuidedMapNodeKind: String, Codable, Sendable {
    case item, aggregate, parentRemainder, limitedVisibility
}

public struct GuidedMapNode: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let parentID: String?
    public let path: String?
    public let displayName: String
    public let allocatedBytes: Int64
    public let category: GuidedMapCategory
    public let measurementState: GuidedMapMeasurementState
    public let kind: GuidedMapNodeKind
    public let childIDs: [String]
}

public struct GuidedMapSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let scanID: String
    public let capturedAt: Date
    public let scopeDescription: String
    public let volumeCapacityBytes: Int64
    public let volumeAvailableBytes: Int64
    public let measuredAllocatedBytes: Int64
    public let evidenceState: GuidedMapMeasurementState
    public let rootID: String
    public let nodes: [GuidedMapNode]
}
```

Implement a pure `GuidedMapBuilder` that consumes the accepted scan presentation snapshot and `DiskDrillDownBuilder` output. It must not read the filesystem and must not accept or expose cleanup authorization.

### Tests first

- [ ] Complete evidence produces a deterministic root and hierarchy.
- [ ] Child allocated bytes never exceed their parent's allocated bytes.
- [ ] A parent's unrepresented bytes become one `parentRemainder` node instead of being double-counted.
- [ ] Small children aggregate deterministically under `otherMeasured` while retaining exact total bytes.
- [ ] Unmeasured or inaccessible capacity appears once as `limitedVisibility`; it does not masquerade as a file or finding.
- [ ] Bounded evidence remains `bounded` even when every returned node has a size.
- [ ] Category mapping uses typed path/classification evidence and falls back to `otherMeasured`; it does not infer ownership.
- [ ] Node IDs are stable for the same scan input and do not contain a raw-path hash that changes between launches.
- [ ] Map nodes contain no reclaim estimate, selection state, or action authority.
- [ ] Encoding and decoding preserves the snapshot exactly.

Run the focused failure:

```bash
swift test --scratch-path "$PWD/.build" --filter GuidedMapTests
```

### Implementation

- [ ] Build the hierarchy from existing drill-down data instead of introducing a second scan traversal.
- [ ] Clamp invalid negative sizes to zero and reject integer overflow with a typed builder error.
- [ ] Sort siblings by allocated bytes descending, then normalized display name, then stable ID.
- [ ] Keep aggregation thresholds configurable in the builder input so UI size does not leak into scan authority.
- [ ] Add `guidedMap: GuidedMapSnapshot?` to `ScanPresentationSnapshot`; update all initializers and fixtures explicitly.
- [ ] Build the map only after the scan request passes the existing cancellation, activity, and request-identity acceptance gates.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter GuidedMapTests
swift test --scratch-path "$PWD/.build" --filter ScanPresentationSnapshot
git diff --check
git add Sources/ReclaimerCore/GuidedMap.swift Sources/ReclaimerCore/ScanPresentationSnapshot.swift Tests/ReclaimerCoreTests/GuidedMapTests.swift
git commit -m "feat: add guided map presentation model"
```

## Task 2: Make Cleanup Planning Honor Explicit User Selection

**Files**

- Modify: `Sources/ReclaimerCore/PlanBuilder.swift`
- Modify: `Tests/ReclaimerCoreTests/PlanBuilderTests.swift`

### Contract

Add an explicit selection entry point while keeping the full finding set available for safety context:

```swift
public func buildPlan(
    from findings: [Finding],
    mode: PlanMode,
    selectedFindingIDs: Set<String>
) throws -> ReclaimPlan
```

The existing overload may delegate with its legacy candidate set for CLI compatibility. The app must use the explicit overload.

### Tests first

- [ ] An empty selection produces an empty plan and cannot become implicit “select all.”
- [ ] Only selected, strictly eligible findings become accepted plan items.
- [ ] Unselected findings remain available to detect nested targets, duplicate paths, and recursive conflicts.
- [ ] Unknown IDs fail closed with a typed error rather than being ignored.
- [ ] Protected, conditional, review-only, stale, active, symlinked, and identity-changed findings stay rejected.
- [ ] Selecting a parent and child cannot create a recursive cleanup plan.
- [ ] Legacy CLI behavior remains covered by existing tests.

### Implementation

- [ ] Resolve selected IDs against the complete finding collection before filtering candidates.
- [ ] Run all existing eligibility and conflict checks after resolution.
- [ ] Return rejection reasons in the existing typed result; do not replace them with UI strings.
- [ ] Add a source-level contract test proving no app caller uses the legacy auto-candidate overload after Task 7.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter PlanBuilderTests
git diff --check
git add Sources/ReclaimerCore/PlanBuilder.swift Tests/ReclaimerCoreTests/PlanBuilderTests.swift
git commit -m "feat: require explicit app cleanup selection"
```

## Task 3: Build A Pure Home Presentation And Suggestion Ranker

**Files**

- Create: `Sources/ReclaimerCore/HomePresentation.swift`
- Create: `Tests/ReclaimerCoreTests/HomePresentationTests.swift`
- Read and reuse: `Sources/ReclaimerCore/GuidedWorkflow.swift`

### Contract

```swift
public enum HomePrimaryAction: Sendable, Equatable {
    case scanMac, cancelScan, reviewSuggestions
    case reviewAccess, exploreLargestFiles, scanAgain
    case verifyCleanup, viewHistory
}

public enum HomeSuggestionKind: String, Codable, Sendable {
    case safeMaintenance, quitAndCheckAgain, nativeMaintenance
    case reviewPersonalFiles, keepByDefault, protected, insufficientEvidence
}

public struct HomeSuggestion: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: HomeSuggestionKind
    public let findingIDs: Set<String>
    public let title: String
    public let explanation: String
    public let consequence: String
    public let allocatedBytes: Int64
    public let estimatedReclaimBytes: Int64?
    public let requiresCurrentScan: Bool
}

public struct HomeSnapshot: Sendable, Equatable {
    public let primaryAction: HomePrimaryAction
    public let suggestions: [HomeSuggestion]
    public let hiddenSuggestionCount: Int
    public let map: GuidedMapSnapshot?
}
```

### Tests first

- [ ] No accepted scan yields `.scanMac` and no suggestions.
- [ ] An active scan yields `.cancelScan` without discarding a saved map.
- [ ] Pending verification outranks cleanup and exploration actions.
- [ ] Limited evidence with no eligible findings yields `.reviewAccess`.
- [ ] Eligible evidence yields at most three suggestion groups and `.reviewSuggestions`.
- [ ] Safe maintenance ranks before personal-file review even when the personal files are larger.
- [ ] Visible groups cover at least 85% of strictly eligible estimated reclaim when three coherent groups can do so.
- [ ] When they cannot, `hiddenSuggestionCount` is non-zero.
- [ ] Allocated bytes and estimated reclaim remain distinct.
- [ ] A suggestion groups typed findings but cannot select them.
- [ ] Stale saved maps remain explorable but do not create actionable current-session suggestions.
- [ ] Ranking is deterministic for equal inputs.

### Implementation

- [ ] Use a pure `HomePresentationBuilder`; pass in scan activity, accepted snapshot, latest saved map, pending verification, and access state.
- [ ] Reuse typed `GuidedWorkflow` classifications instead of matching English strings.
- [ ] Apply primary-action precedence: cancel scan, verify, first scan, review access, review suggestions, explore, scan again/history.
- [ ] Rank first by eligibility/freshness, then conservative reclaim, confidence, consequence clarity, and disk pressure.
- [ ] Keep copy construction centralized and covered by snapshot-like unit assertions.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter HomePresentationTests
swift test --scratch-path "$PWD/.build" --filter GuidedWorkflowTests
git diff --check
git add Sources/ReclaimerCore/HomePresentation.swift Tests/ReclaimerCoreTests/HomePresentationTests.swift
git commit -m "feat: add regular-user home presentation"
```

## Task 4: Persist The Latest Trustworthy Map As Display-Only Evidence

**Files**

- Create: `Sources/ReclaimerCore/GuidedMapStore.swift`
- Create: `Tests/ReclaimerCoreTests/GuidedMapStoreTests.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardDependencies.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Modify: `Tests/MacDiskReclaimerAppTests/DashboardScanOperationTests.swift`

### Store rules

- [ ] Store append-only JSON snapshots beneath the existing private application-support root.
- [ ] Create the directory with mode `0700` and files with mode `0600`.
- [ ] Refuse symlinks, non-regular files, files larger than 8 MiB, unsupported schema versions, malformed JSON, and path escapes.
- [ ] Load newest valid snapshot; quarantine nothing automatically and never delete ambiguous files.
- [ ] Bound retention using the repository's established explicit-retention pattern.
- [ ] Store only `GuidedMapSnapshot`; never persist findings, cleanup selections, plans, authorizations, or execution sessions in this store.

### Tests first

- [ ] Save/load round trip.
- [ ] Newest valid snapshot wins.
- [ ] Corrupt newest file falls back to the previous valid file with a typed diagnostic.
- [ ] Oversized, symlinked, non-regular, escaped, and unsupported snapshots are rejected.
- [ ] Permissions are private.
- [ ] Cancelled, failed, and stale-request scans leave the prior accepted map unchanged.
- [ ] A successful accepted scan persists exactly once after acceptance.

### Dependency boundary

Add loader/saver protocols to `DashboardDependencies` so app tests use in-memory fakes. Load the saved map during model initialization without triggering a scan. The saved map may populate Home and Explore, but it must not populate current findings or authorize cleanup.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter GuidedMapStoreTests
swift test --scratch-path "$PWD/.build" --filter DashboardScanOperationTests
git diff --check
git add Sources/ReclaimerCore/GuidedMapStore.swift Tests/ReclaimerCoreTests/GuidedMapStoreTests.swift Sources/MacDiskReclaimerApp/DashboardDependencies.swift Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift Tests/MacDiskReclaimerAppTests/DashboardScanOperationTests.swift
git commit -m "feat: persist display-only guided maps"
```

## Task 5: Replace Feature Navigation With Home, Explore, And History

**Files**

- Modify: `Sources/MacDiskReclaimerApp/DashboardSection.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardSidebarView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardCommands.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardSettingsView.swift`
- Create: `Tests/MacDiskReclaimerAppTests/DashboardNavigationTests.swift`
- Modify: `Tests/ReclaimerCoreTests/AppAccessibilityContractTests.swift`

### Tests first

- [ ] Primary destination enum contains exactly `home`, `explore`, and `history`.
- [ ] Every legacy scene-restoration ID maps deterministically to one of the three destinations or Advanced Settings.
- [ ] Remote Targets, developer storage, permissions, scopes, protection, automation, rules, diagnostics, and release trust remain reachable in Settings.
- [ ] `Command-1`, `Command-2`, and `Command-3` select Home, Explore, and History.
- [ ] `Command-R` starts or refreshes a scan only after user input.
- [ ] `Command-,` opens Settings.
- [ ] No regular-user menu item directly creates a plan, runs a dry run, or executes cleanup.

### Implementation

- [ ] Introduce `DashboardPrimaryDestination` for the three regular-user routes.
- [ ] Introduce a separate typed `AdvancedSettingsDestination` rather than retaining 20+ fake primary destinations.
- [ ] Reduce the source-list sidebar to three rows, with scan activity and disk-pressure status as non-navigation chrome.
- [ ] Host existing advanced views from `DashboardSettingsView` without removing their behavior.
- [ ] Update deep-link and scene restoration migration tables before deleting old cases.
- [ ] Keep all selection state typed; do not restore navigation by matching displayed labels.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter DashboardNavigationTests
swift test --scratch-path "$PWD/.build" --filter AppAccessibilityContractTests
git diff --check
git add Sources/MacDiskReclaimerApp/DashboardSection.swift Sources/MacDiskReclaimerApp/DashboardSidebarView.swift Sources/MacDiskReclaimerApp/DashboardView.swift Sources/MacDiskReclaimerApp/DashboardCommands.swift Sources/MacDiskReclaimerApp/DashboardSettingsView.swift Tests/MacDiskReclaimerAppTests/DashboardNavigationTests.swift Tests/ReclaimerCoreTests/AppAccessibilityContractTests.swift
git commit -m "feat: focus navigation on three user tasks"
```

## Task 6: Implement A Deterministic Treemap And Accessible Outline

**Files**

- Create: `Sources/MacDiskReclaimerApp/GuidedMap/TreemapLayout.swift`
- Create: `Sources/MacDiskReclaimerApp/GuidedMap/GuidedTreemapView.swift`
- Create: `Sources/MacDiskReclaimerApp/GuidedMap/GuidedMapOutlineView.swift`
- Create: `Sources/MacDiskReclaimerApp/GuidedMap/GuidedMapInspectorView.swift`
- Create: `Tests/MacDiskReclaimerAppTests/TreemapLayoutTests.swift`
- Create: `Tests/MacDiskReclaimerAppTests/GuidedMapInteractionTests.swift`
- Modify: `Sources/MacDiskReclaimerApp/AccessibilityIDs.swift`

### Layout tests first

- [ ] Empty and zero-byte inputs return no invalid rectangles.
- [ ] Every rectangle is finite, non-negative, and within the supplied bounds.
- [ ] Sibling rectangles do not overlap beyond a documented floating-point tolerance.
- [ ] Rectangle areas are proportional to allocated bytes within tolerance.
- [ ] The same sorted inputs and bounds produce identical rectangles.
- [ ] Extreme aspect ratios, one child, thousands of tiny children, and integer limits remain valid.
- [ ] Aggregated and limited-visibility nodes receive normal layout treatment without inventing bytes.

Implement a pure squarified layout function:

```swift
struct TreemapLayout {
    func rectangles(
        for nodes: [GuidedMapNode],
        in bounds: CGRect
    ) -> [String: CGRect]
}
```

### Interaction and accessibility

- [ ] Single click synchronizes treemap and outline selection.
- [ ] Double click or Return drills into a node with children.
- [ ] Breadcrumbs navigate to every ancestor and expose a Back action.
- [ ] Space invokes Quick Look only for eligible file-backed nodes.
- [ ] Context actions are limited to Quick Look, Reveal in Finder, Copy Path, and allowed Open in Terminal.
- [ ] The inspector explains name, category, allocated size, measurement state, scope, and important non-claims.
- [ ] The outline exposes the identical hierarchy sorted by allocated size and is fully keyboard navigable.
- [ ] VoiceOver labels include hierarchy level, category, allocated size, evidence state, and available action.
- [ ] Color is never the only category or state signal.
- [ ] Reduced motion disables drill animations; increased contrast remains legible.
- [ ] No view in `GuidedMap/` imports or calls `PlanBuilder`, dry-run, Trash, deletion, or authorization APIs.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter TreemapLayoutTests
swift test --scratch-path "$PWD/.build" --filter GuidedMapInteractionTests
git diff --check
git add Sources/MacDiskReclaimerApp/GuidedMap Tests/MacDiskReclaimerAppTests/TreemapLayoutTests.swift Tests/MacDiskReclaimerAppTests/GuidedMapInteractionTests.swift Sources/MacDiskReclaimerApp/AccessibilityIDs.swift
git commit -m "feat: add accessible guided treemap"
```

## Task 7: Build Home And The Explicit Cleanup Review Journey

**Files**

- Create: `Sources/MacDiskReclaimerApp/Home/HomeView.swift`
- Create: `Sources/MacDiskReclaimerApp/Home/HomeSuggestionView.swift`
- Create: `Sources/MacDiskReclaimerApp/Home/CleanupReviewView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Modify: `Sources/MacDiskReclaimerApp/GuidedSummaryView.swift`
- Create: `Tests/MacDiskReclaimerAppTests/HomeJourneyTests.swift`
- Modify: `Tests/MacDiskReclaimerAppTests/DashboardExecutionReconciliationTests.swift`

### State boundary

Add a dedicated `reviewSelectionIDs: Set<String>` owned by the current accepted scan session. Clear it when the accepted scan changes, the review closes after execution, or evidence becomes invalid. Never initialize it from visible suggestions or map selection.

### Tests first

- [ ] First launch shows capacity, scope preview, one `Scan your Mac` action, and no map claim.
- [ ] Starting a scan is only possible through explicit user action.
- [ ] Active scan shows scope, progress, measured-item count, and Cancel.
- [ ] A saved map renders immediately with capture time, scope, and complete/bounded/limited state.
- [ ] Home displays at most three suggestions and exactly one primary next action.
- [ ] `Review suggestions` opens a checklist with nothing selected.
- [ ] Toggling a row changes only `reviewSelectionIDs`, not findings or map selection.
- [ ] `Select safe maintenance` is secondary and selects only IDs accepted by a fresh core planning pass.
- [ ] Protected, conditional, review-only, stale, active, symlinked, and changed items stay unavailable or unselected.
- [ ] `Check safely` rebuilds the plan from the explicit selection and runs the existing dry-run path.
- [ ] Identity/open-handle changes discovered during dry run appear as skipped with reasons.
- [ ] Execution remains disabled until dry run and one-use authorization succeed.
- [ ] Completion records receipts and leads to verification without claiming reclaim from estimates.

### Implementation

- [ ] Derive `HomeSnapshot` on accepted immutable presentation state, off the main actor when computation is material.
- [ ] Render the treemap as the largest Home element, with pressure/evidence headline above and suggestion cards below or beside it.
- [ ] Use plain-language steps: Choose items, Review cleanup, Check safely, Move to Trash, Verify result.
- [ ] Keep “Select safe maintenance” inside review, visually secondary, and require a user click.
- [ ] Route `Check safely` through `PlanBuilder.buildPlan(...selectedFindingIDs:)` and the existing dry-run coordinator.
- [ ] Remove or redirect duplicate Summary/queue surfaces only after equivalent Home, review, and History behavior is covered.
- [ ] Preserve cancellation and stale-request guards around every asynchronous transition.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter HomeJourneyTests
swift test --scratch-path "$PWD/.build" --filter DashboardExecutionReconciliationTests
swift test --scratch-path "$PWD/.build" --filter DashboardScanOperationTests
git diff --check
git add Sources/MacDiskReclaimerApp/Home Sources/MacDiskReclaimerApp/DashboardModel.swift Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift Sources/MacDiskReclaimerApp/GuidedSummaryView.swift Tests/MacDiskReclaimerAppTests/HomeJourneyTests.swift Tests/MacDiskReclaimerAppTests/DashboardExecutionReconciliationTests.swift
git commit -m "feat: add explicit guided cleanup review"
```

## Task 8: Focus Explore, History, And Advanced Settings

**Files**

- Create: `Sources/MacDiskReclaimerApp/Explore/ExploreView.swift`
- Create: `Sources/MacDiskReclaimerApp/Explore/ExploreFilter.swift`
- Create: `Sources/MacDiskReclaimerApp/History/HistoryView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardSettingsView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+Reviews.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift`
- Create: `Tests/MacDiskReclaimerAppTests/ExplorePresentationTests.swift`
- Create: `Tests/MacDiskReclaimerAppTests/HistoryPresentationTests.swift`

### Explore acceptance

- [ ] Uses the same map snapshot, breadcrumb, inspector, and outline as Home.
- [ ] Supports typed category, minimum-size, evidence-state, and item-kind filters plus text search.
- [ ] Supports sort by allocated size, name, category, and modified date only when that date is measured.
- [ ] Presents Applications and leftovers as filters/views, not another primary destination.
- [ ] Does not show estimated reclaim as allocated size or permit map-driven cleanup selection.

### History acceptance

- [ ] Reuses current audit, native-tool receipt, recovery, scan-history, and verification models.
- [ ] Separates estimated reclaim, observed movement to Trash, native-tool reported values, and verified free-space change.
- [ ] Shows the exact evidence time and whether a result is current, historical, bounded, or incomplete.
- [ ] Provides recovery guidance and receipt export without granting cleanup authority.

### Settings acceptance

- [ ] Permissions/access, scan scopes, saved scope sets, exclusions/protections, rules, automation, developer storage, Remote Targets, diagnostics, release trust, and CLI guidance remain reachable.
- [ ] Advanced settings routes do not appear as Home suggestions unless a typed current state requires the user to review access or use a native maintenance tool.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter ExplorePresentationTests
swift test --scratch-path "$PWD/.build" --filter HistoryPresentationTests
swift test --scratch-path "$PWD/.build" --filter DashboardAuditLoadingTests
git diff --check
git add Sources/MacDiskReclaimerApp/Explore Sources/MacDiskReclaimerApp/History Sources/MacDiskReclaimerApp/DashboardContentViews.swift Sources/MacDiskReclaimerApp/DashboardSettingsView.swift Sources/MacDiskReclaimerApp/DashboardModel+Reviews.swift Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift Tests/MacDiskReclaimerAppTests/ExplorePresentationTests.swift Tests/MacDiskReclaimerAppTests/HistoryPresentationTests.swift
git commit -m "feat: focus explore history and settings"
```

## Task 9: Prove Responsive Layout, Accessibility, And Performance

**Files**

- Create: `docs/QA_V0.4_GUIDED_MAP.md`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Modify: `Sources/MacDiskReclaimerApp/Home/HomeView.swift`
- Modify: `Sources/MacDiskReclaimerApp/GuidedMap/GuidedTreemapView.swift`
- Modify: `Tests/MacDiskReclaimerAppTests/TreemapLayoutTests.swift`
- Modify: `Tests/ReclaimerCoreTests/AppAccessibilityContractTests.swift`

### Automated gates

- [ ] Minimum supported window: 820 x 620 points with no hidden primary action or horizontal content clipping.
- [ ] Reference window: 1180 x 760 points with map, headline, suggestions, and primary action visible without confusing scroll ownership.
- [ ] Wide window: 1440 x 900 points uses space without stretching readable copy beyond a sensible measure.
- [ ] Dynamic Type/accessibility text sizes preserve complete labels and keyboard reachability.
- [ ] Every icon-only control has a label and help text.
- [ ] Treemap and outline selection, focus, and breadcrumb state remain synchronized.
- [ ] In a release build, layout for 5,000 already-built nodes completes within 500 ms on the test machine; record machine details and percentile rather than claiming a universal guarantee.
- [ ] Main-actor tests prove scan, map construction, grouping, filtering, and persistence do not block SwiftUI rendering.

### Manual QA matrix

Document and capture evidence for:

- [ ] Light, dark, increased contrast, reduced motion, and grayscale/color-filter use.
- [ ] VoiceOver traversal from sidebar through headline, map/outline, suggestions, review, and History.
- [ ] Keyboard-only scan, cancel, map drill, breadcrumb, outline selection, Quick Look, review selection, dry run, and dismissal.
- [ ] Complete, bounded, limited, stale, cancelled, failed, and no-eligible-finding states.
- [ ] A long filename, deep hierarchy, thousands of tiny nodes, empty disk fixture, and inaccessible scope.

Verify and commit:

```bash
swift test --scratch-path "$PWD/.build" --filter TreemapLayoutTests
swift test --scratch-path "$PWD/.build" --filter AppAccessibilityContractTests
swift build -c release --scratch-path "$PWD/.build"
git diff --check
git add docs/QA_V0.4_GUIDED_MAP.md Sources/MacDiskReclaimerApp/DashboardView.swift Sources/MacDiskReclaimerApp/Home/HomeView.swift Sources/MacDiskReclaimerApp/GuidedMap/GuidedTreemapView.swift Tests/MacDiskReclaimerAppTests/TreemapLayoutTests.swift Tests/ReclaimerCoreTests/AppAccessibilityContractTests.swift
git commit -m "test: prove guided map usability boundaries"
```

## Task 10: Expand Packaged-App E2E And Product Documentation

**Files**

- Modify: `Tests/AppE2E/RyddiAXHarness.swift`
- Modify: `scripts/make-app-e2e-fixture.sh`
- Modify: `scripts/run-packaged-app-e2e.sh`
- Modify: `scripts/app-e2e-smoke.sh`
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `docs/COMPETITIVE.md`
- Modify: `docs/SCREENSHOTS.md`
- Modify: `scripts/release-check.sh`
- Modify: `docs/superpowers/plans/2026-07-14-ryddi-v0.4-guided-cleanup-and-e2e.md`

### Data-driven packaged scenarios

- [ ] First launch has no map claim and does not scan automatically.
- [ ] User starts and cancels a scan; a prior trustworthy map remains visible.
- [ ] User completes scans with complete, bounded, and limited evidence.
- [ ] Home shows no more than three suggestions and one primary action.
- [ ] Cleanup review opens with nothing selected.
- [ ] User explicitly selects one eligible item and safely checks only that item.
- [ ] `Select safe maintenance` selects only currently accepted safe-maintenance items.
- [ ] Changed identity, symlink substitution, nested target, protected path, active process, and open handle all fail closed.
- [ ] Authorized items move to Trash; receipt and recovery guidance appear in History.
- [ ] Verification reports observed results separately from prior estimates.
- [ ] Treemap, outline, breadcrumbs, Quick Look, Finder reveal, and keyboard commands work in the packaged app.
- [ ] Advanced settings remain reachable while absent from primary navigation.

Use only disposable fixtures. Never point E2E cleanup at real user data. Add stable accessibility IDs for semantics, not visual coordinates or English-copy matching.

### Documentation

- [ ] Rewrite the first-run README around “Scan your Mac -> understand the map -> review suggestions -> check safely -> move to Trash -> verify.”
- [ ] Explain that no item is preselected and the map never deletes.
- [ ] Document complete, bounded, limited, and stale evidence.
- [ ] Update the competitive document with the honest DaisyDisk/SquirrelDisk strengths adopted and Ryddi's safety differentiators.
- [ ] Replace screenshot inventory with the three primary destinations plus cleanup review and advanced Settings.
- [ ] Mark the conflicting tasks in the old v0.4 plan as superseded by this plan; preserve unrelated Remote Targets and release work.

### Full verification

```bash
df -h /System/Volumes/Data
swift test --scratch-path "$PWD/.build"
swift build -c release --scratch-path "$PWD/.build"
bash Tests/ScriptTests/run.sh
bash scripts/app-e2e-smoke.sh
bash scripts/run-packaged-app-e2e.sh
bash scripts/release-check.sh
git diff --check
git status --short
```

Record exact commands, results, packaged app identity, and any manual-only gaps in `docs/QA_V0.4_GUIDED_MAP.md`. Do not claim signed/notarized release readiness from an unsigned local rehearsal.

Commit the final implementation/doc slice:

```bash
git add Tests/AppE2E/RyddiAXHarness.swift scripts/make-app-e2e-fixture.sh scripts/run-packaged-app-e2e.sh scripts/app-e2e-smoke.sh README.md FEATURES.md docs/COMPETITIVE.md docs/SCREENSHOTS.md scripts/release-check.sh docs/superpowers/plans/2026-07-14-ryddi-v0.4-guided-cleanup-and-e2e.md docs/QA_V0.4_GUIDED_MAP.md
git commit -m "test: prove the guided map journey end to end"
```

## Final Review Gates

### Gate A: Understanding Without Authority

- [ ] First launch is understandable without prior Ryddi knowledge.
- [ ] The user starts scans explicitly.
- [ ] The map explains allocated space and evidence limits without cleanup authority.
- [ ] Cancel/failure/stale results cannot replace trustworthy saved evidence.

### Gate B: Explicit And Safe Intent

- [ ] Cleanup review starts empty.
- [ ] Every selected cleanup item came from a user action in the current accepted session.
- [ ] Core planning and dry-run gates remain the only path to execution.
- [ ] Final identity/open-handle revalidation and one-use authorization still fail closed.

### Gate C: Regular-User Usability

- [ ] Home, Explore, and History cover the primary journey.
- [ ] Advanced capabilities remain reachable without competing with first use.
- [ ] Treemap and outline reach functional parity for keyboard and VoiceOver users.
- [ ] Responsive, contrast, motion, and performance evidence is recorded.

### Gate D: Evidence-Backed Delivery

- [ ] Unit, app, script, packaged E2E, and release-check commands pass on the exact reviewed commit.
- [ ] Documentation and screenshots match the packaged app.
- [ ] Remote Targets batching and signed release work are reported separately unless executed and proven.
- [ ] The worktree is clean and the exact SHA is recorded before PR handoff.

## Execution Handoff

Recommended order is strictly Tasks 1 through 10 because each UI layer depends on the preceding authority and presentation contracts. Tasks 1-4 form the model and persistence checkpoint; Tasks 5-8 form the product checkpoint; Tasks 9-10 form the proof checkpoint.

At each checkpoint, inspect the diff for accidental safety weakening and run the full relevant test target before continuing. If an existing type differs from the interface sketched here, preserve the behavioral contract and update the plan in the same commit with a short rationale instead of forcing an incompatible API.
