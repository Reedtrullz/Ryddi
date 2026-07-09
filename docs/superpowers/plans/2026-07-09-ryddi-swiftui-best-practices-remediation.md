# Ryddi SwiftUI Best Practices Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Ryddi's macOS app shell closer to native SwiftUI best practices while closing the app reclaim session-safety gap found in review.

**Architecture:** Keep the existing SwiftPM app target and `ReclaimerCore` contracts. Refactor the app from a single giant source file toward focused shell, sidebar, commands, settings, and model files, with typed navigation and source-level layout guard tests. Preserve current cleanup behavior except for the safety fix that passes the current scan session into perform-mode execution.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, macOS 14+, XCTest source-shape tests, existing Ryddi CLI/core/app targets.

## Global Constraints

- Minimum OS remains macOS 14+.
- No telemetry, path upload, remote AI analysis, root helper, or Mac App Store sandboxing.
- Do not add new destructive cleanup capabilities in this slice.
- Preserve report-first automation and Remote Targets; do not add remote execute, prune, reset, or unattended destructive actions.
- Preserve GarageBand/Logic assets, browser profiles, VM/container disks, Codex sessions/memories/config/auth, credentials, app state DBs, and unknown user data by default.
- Before long build/test loops, run `df -h /System/Volumes/Data`; stop if free space is below `50Gi`.
- Use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"`.
- Use focused source-shape tests first, then build/full-test verification.
- Keep the installed-app release posture conservative: do not claim signed/notarized `v0.3.0` unless the signed release gate is actually run and accepted.

---

## File Structure

Create or modify these app files:

- Create `Sources/MacDiskReclaimerApp/RyddiWindowLayout.swift`
  - Owns `RyddiWindowLayout` and `DashboardResponsiveGrid`.
- Create `Sources/MacDiskReclaimerApp/DashboardSection.swift`
  - Owns typed dashboard sections, sidebar groups, labels, symbols, and screenshot launch mapping.
- Create `Sources/MacDiskReclaimerApp/DashboardView.swift`
  - Owns `DashboardView`, root `NavigationSplitView`, detail routing, toolbar, confirmation dialog, scene storage, and focused command action export.
- Create `Sources/MacDiskReclaimerApp/DashboardSidebarView.swift`
  - Owns native source-list sidebar rows with `List(selection:)`; no rich findings embedded in the sidebar.
- Create `Sources/MacDiskReclaimerApp/DashboardCommands.swift`
  - Owns focused command values and scene command menus/keyboard shortcuts.
- Create `Sources/MacDiskReclaimerApp/DashboardSettingsView.swift`
  - Owns native Settings scene content, `@AppStorage` keys, and persisted default preferences.
- Create `Sources/MacDiskReclaimerApp/StatusMenuView.swift`
  - Owns `StatusMenuView` and `StatusMenuModel`.
- Create `Sources/MacDiskReclaimerApp/PathActions.swift`
  - Owns app-level AppKit path/open/settings helpers currently embedded in the monolith.
- Create `Sources/MacDiskReclaimerApp/DashboardModel.swift`
  - Owns `DashboardModel` stored properties, computed properties, and init-only state.
- Create `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
  - Owns scan, plan, dry-run, reclaim, and scan-session recording methods.
- Create `Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift`
  - Owns audit, holding, recovery, and saved scope loading methods.
- Create `Sources/MacDiskReclaimerApp/DashboardModel+Reviews.swift`
  - Owns local review-report methods for Downloads, Trash, Browser, Packages, Projects, Xcode, Containers, Apps, and Agents.
- Create `Sources/MacDiskReclaimerApp/DashboardModel+Remote.swift`
  - Owns Remote Targets model methods.
- Create `Sources/MacDiskReclaimerApp/DashboardModel+Exports.swift`
  - Owns report/export methods.
- Modify `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
  - Keep only `@main`, scenes, and scene-level command registration.
- Modify `Sources/MacDiskReclaimerApp/AppReviewViews.swift`
  - Make Apps & Leftovers detail/rail layout adapt using `ViewThatFits` and explicit table scrolling.
- Modify `Sources/MacDiskReclaimerApp/DashboardDemoData.swift`
  - Keep screenshot data, but consume typed `DashboardSection` launch mapping.
- Modify `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`
  - Add guardrails for session-safe reclaim, typed navigation, native sidebar, commands, settings, file split, and adaptive Apps layout.

Do not move `ReclaimerCore` types in this plan.

---

### Task 1: App Perform-Mode Scan Session Gate

**Files:**
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Consumes: `DashboardModel.currentScanSession: ScanSession?`
- Consumes: `ExecutorConfiguration.init(userPathPolicy:currentScanSession:)`
- Produces: `DashboardModel.reclaimSelected()` perform path that passes the current session to `ReclaimerExecutor`

- [ ] **Step 1: Add the failing source-shape test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testAppPerformReclaimPassesCurrentScanSessionToExecutor() throws {
    let source = try appSource()
    let start = try XCTUnwrap(source.range(of: "func reclaimSelected() async"))
    let end = try XCTUnwrap(source[start.lowerBound...].range(of: "\n    func exportEvidenceReport"))
    let reclaimSource = String(source[start.lowerBound..<end.lowerBound])

    XCTAssertTrue(
        reclaimSource.contains("let session = currentScanSession"),
        "The app perform path should capture the current ScanSession before hopping into the detached executor task."
    )
    XCTAssertTrue(
        reclaimSource.contains("ExecutorConfiguration(userPathPolicy: policy, currentScanSession: session)"),
        "The app perform path should pass the current ScanSession into ReclaimerExecutor just like dry-run does."
    )
    XCTAssertFalse(
        reclaimSource.contains("ExecutorConfiguration(userPathPolicy: policy)\n"),
        "Perform-mode reclaim must not drop the current ScanSession final gate."
    )
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppPerformReclaimPassesCurrentScanSessionToExecutor
```

Expected: FAIL because `reclaimSelected()` does not contain `let session = currentScanSession` and does not pass `currentScanSession` into `ExecutorConfiguration`.

- [ ] **Step 3: Patch `reclaimSelected()`**

In `DashboardModel.reclaimSelected()`, replace this block:

```swift
let includeUserRules = includeUserRulesInScans
let receipt = try await Task.detached {
    let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
    let policy = UserPathPolicyStore().load()
    return ReclaimerExecutor(
        openFileChecker: LsofOpenFileChecker(),
        configuration: ExecutorConfiguration(userPathPolicy: policy)
    )
        .execute(
            plan: currentPlan,
            mode: .perform,
            ruleVersion: ruleVersion,
            userConfirmed: true
        )
}.value
```

with:

```swift
let includeUserRules = includeUserRulesInScans
let session = currentScanSession
let receipt = try await Task.detached {
    let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
    let policy = UserPathPolicyStore().load()
    return ReclaimerExecutor(
        openFileChecker: LsofOpenFileChecker(),
        configuration: ExecutorConfiguration(userPathPolicy: policy, currentScanSession: session)
    )
        .execute(
            plan: currentPlan,
            mode: .perform,
            ruleVersion: ruleVersion,
            userConfirmed: true
        )
}.value
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppPerformReclaimPassesCurrentScanSessionToExecutor
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "fix: preserve app scan session during reclaim"
```

---

### Task 2: Typed Dashboard Sections And Scene Restoration

**Files:**
- Create: `Sources/MacDiskReclaimerApp/DashboardSection.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardDemoData.swift`
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Produces: `enum DashboardSection: String, CaseIterable, Identifiable, Hashable`
- Produces: `enum DashboardSidebarGroup: String, CaseIterable, Identifiable`
- Produces: `DashboardLaunchOptions.initialSection: DashboardSection`
- Produces: `DashboardSection.fromLegacyID(_:) -> DashboardSection`
- Produces: window-scoped scene storage key `dashboard.selectedSectionID`

- [ ] **Step 1: Add the failing typed-navigation test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testDashboardNavigationUsesTypedSectionsAndSceneStorage() throws {
    let source = try appSource()
    let sectionSource = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardSection.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(sectionSource.contains("enum DashboardSection: String, CaseIterable, Identifiable, Hashable"))
    XCTAssertTrue(sectionSource.contains("case summary = \"Summary\""))
    XCTAssertTrue(sectionSource.contains("case remoteTargets = \"RemoteTargets\""))
    XCTAssertTrue(sectionSource.contains("static func fromLegacyID(_ rawValue: String) -> DashboardSection"))
    XCTAssertTrue(source.contains("@SceneStorage(\"dashboard.selectedSectionID\")"))
    XCTAssertFalse(source.contains("@State private var selectedSection ="))
    XCTAssertFalse(source.contains("selectedSection == \""))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardNavigationUsesTypedSectionsAndSceneStorage
```

Expected: FAIL because `DashboardSection.swift` does not exist and `DashboardView` still stores a raw string.

- [ ] **Step 3: Create `DashboardSection.swift`**

Create `Sources/MacDiskReclaimerApp/DashboardSection.swift` with:

```swift
import SwiftUI

enum DashboardSidebarGroup: String, CaseIterable, Identifiable {
    case start = "Start"
    case generalMac = "General Mac"
    case developer = "Developer"
    case trust = "Trust"

    var id: String { rawValue }
}

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case summary = "Summary"
    case queues = "Queues"
    case largeOld = "LargeOld"
    case apps = "Apps"
    case downloads = "Downloads"
    case duplicates = "Duplicates"
    case browsers = "Browsers"
    case deviceBackups = "DeviceBackups"
    case trash = "Trash"
    case packages = "Packages"
    case projects = "Projects"
    case xcode = "Xcode"
    case containers = "Containers"
    case remoteTargets = "RemoteTargets"
    case agents = "Agents"
    case permissions = "Permissions"
    case active = "Active"
    case scopes = "Scopes"
    case policy = "Policy"
    case audit = "Audit"
    case recovery = "Recovery"
    case holding = "Holding"
    case automation = "Automation"
    case rules = "Rules"
    case features = "Features"
    case finding = "Finding"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Summary"
        case .queues: "Review Queues"
        case .largeOld: "Large & Old Files"
        case .apps: "Apps & Leftovers"
        case .downloads: "Downloads"
        case .duplicates: "Duplicates"
        case .browsers: "Browser Caches"
        case .deviceBackups: "Device Backups"
        case .trash: "Trash"
        case .packages: "Package Caches"
        case .projects: "Project Dependencies"
        case .xcode: "Xcode"
        case .containers: "Containers"
        case .remoteTargets: "Remote Targets"
        case .agents: "AI Agent Storage"
        case .permissions: "Permissions"
        case .active: "Active Handles"
        case .scopes: "Scope Sets"
        case .policy: "Protections"
        case .audit: "Audit History"
        case .recovery: "Recovery Center"
        case .holding: "Holding Area"
        case .automation: "Automation"
        case .rules: "Rule Catalog"
        case .features: "Feature Matrix"
        case .finding: "Finding"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "gauge.with.dots.needle"
        case .queues: "tray.full"
        case .largeOld: "archivebox"
        case .apps: "app.dashed"
        case .downloads: "arrow.down.circle"
        case .duplicates: "doc.on.doc"
        case .browsers: "globe"
        case .deviceBackups: "iphone"
        case .trash: "trash"
        case .packages: "shippingbox"
        case .projects: "folder"
        case .xcode: "hammer"
        case .containers: "cube.box"
        case .remoteTargets: "server.rack"
        case .agents: "brain.head.profile"
        case .permissions: "lock.shield"
        case .active: "waveform.path.ecg"
        case .scopes: "scope"
        case .policy: "hand.raised"
        case .audit: "clock.arrow.circlepath"
        case .recovery: "arrow.uturn.backward.circle"
        case .holding: "tray"
        case .automation: "calendar.badge.clock"
        case .rules: "list.bullet.rectangle"
        case .features: "square.grid.2x2"
        case .finding: "doc.text.magnifyingglass"
        }
    }

    var sidebarGroup: DashboardSidebarGroup? {
        switch self {
        case .summary, .queues, .largeOld:
            .start
        case .apps, .downloads, .duplicates, .browsers, .deviceBackups, .trash:
            .generalMac
        case .packages, .projects, .xcode, .containers, .remoteTargets, .agents:
            .developer
        case .permissions, .active, .scopes, .policy, .audit, .recovery, .holding, .automation, .rules, .features:
            .trust
        case .finding:
            nil
        }
    }

    static var sidebarSections: [DashboardSection] {
        allCases.filter { $0.sidebarGroup != nil }
    }

    static func fromLegacyID(_ rawValue: String) -> DashboardSection {
        DashboardSection(rawValue: rawValue) ?? .summary
    }
}

enum DashboardLaunchOptions {
    static var isScreenshotDemo: Bool {
        ProcessInfo.processInfo.environment["RYDDI_SCREENSHOT_DEMO"] == "1"
    }

    static var initialSection: DashboardSection {
        guard isScreenshotDemo else { return .summary }
        let raw = ProcessInfo.processInfo.environment["RYDDI_SCREENSHOT_SECTION"] ?? DashboardSection.summary.rawValue
        switch raw.lowercased() {
        case "queues", "review-queues":
            return .queues
        case "apps", "app-review", "apps-and-leftovers":
            return .apps
        case "remote", "remote-targets":
            return .remoteTargets
        default:
            return DashboardSection.fromLegacyID(raw)
        }
    }

    static var initialSectionID: String {
        initialSection.rawValue
    }
}
```

- [ ] **Step 4: Replace raw selected-section state in `DashboardView`**

Replace:

```swift
@State private var selectedSection = DashboardLaunchOptions.initialSection
```

with:

```swift
@SceneStorage("dashboard.selectedSectionID") private var selectedSectionID = DashboardLaunchOptions.initialSectionID
```

Add these helpers inside `DashboardView`:

```swift
private var selectedSection: DashboardSection {
    DashboardSection(rawValue: selectedSectionID) ?? .summary
}

private func selectSection(_ section: DashboardSection) {
    selectedFinding = nil
    selectedSectionID = section.rawValue
}

private func selectLegacySection(_ sectionID: String) {
    selectSection(DashboardSection.fromLegacyID(sectionID))
}
```

Replace the detail `if selectedSection == "..."` chain with this complete switch:

```swift
switch selectedSection {
case .features:
    CapabilityMatrixView()
case .rules:
    RuleCatalogView()
case .apps:
    AppReviewView(model: model)
case .queues:
    ReviewQueuesView(model: model) { finding in
        selectedFinding = finding.id
        selectedSectionID = DashboardSection.finding.rawValue
    }
case .largeOld:
    LargeOldReviewView(model: model)
case .duplicates:
    DuplicateReviewView(model: model)
case .downloads:
    DownloadsReviewView(model: model)
case .browsers:
    BrowserCacheReviewView(model: model)
case .packages:
    PackageCacheReviewView(model: model) { section in
        selectedFinding = nil
        selectedSectionID = DashboardSection.fromLegacyID(section).rawValue
    }
case .projects:
    ProjectDependencyReviewView(model: model)
case .deviceBackups:
    DeviceBackupReviewView(model: model)
case .xcode:
    XcodeReviewView(model: model)
case .trash:
    TrashReviewView(model: model)
case .containers:
    ContainerInventoryView(model: model)
case .remoteTargets:
    RemoteTargetsView(model: model)
case .agents:
    AgentStorageReviewView(model: model)
case .permissions:
    PermissionOnboardingView(model: model)
case .active:
    ActiveFileReviewView(model: model)
case .scopes:
    SavedScopeSetView(model: model)
case .policy:
    UserPathPolicyView(model: model)
case .audit:
    AuditHistoryView(model: model)
case .recovery:
    RecoveryCenterView(model: model)
case .holding:
    HoldingView(model: model)
case .automation:
    AutomationView(model: model)
case .finding:
    if let finding = model.findings.first(where: { $0.id == selectedFinding }) {
        FindingDetailView(model: model, finding: finding, planItem: model.planItem(for: finding.id))
    } else {
        OverviewView(
            model: model,
            onReclaim: { showingReclaimConfirmation = true },
            navigate: selectLegacySection
        )
    }
case .summary:
    OverviewView(
        model: model,
        onReclaim: { showingReclaimConfirmation = true },
        navigate: selectLegacySection
    )
}
```

Replace every `selectedSection = "Finding"` with:

```swift
selectedSectionID = DashboardSection.finding.rawValue
```

Replace every `selectedSection == "RemoteTargets"` with:

```swift
selectedSection == .remoteTargets
```

- [ ] **Step 5: Remove the old `DashboardLaunchOptions` from `MacDiskReclaimerApp.swift`**

Delete the old raw-string `DashboardLaunchOptions` declaration from `MacDiskReclaimerApp.swift`. `DashboardDemoData.swift` should keep calling `DashboardLaunchOptions.isScreenshotDemo`; the type now lives in `DashboardSection.swift`.

- [ ] **Step 6: Run the focused test and verify it passes**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardNavigationUsesTypedSectionsAndSceneStorage
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacDiskReclaimerApp/DashboardSection.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift Sources/MacDiskReclaimerApp/DashboardDemoData.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "refactor: type dashboard navigation"
```

---

### Task 3: Native Source-List Sidebar

**Files:**
- Create: `Sources/MacDiskReclaimerApp/DashboardSidebarView.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Consumes: `DashboardSection.sidebarSections`
- Consumes: `DashboardSection.sidebarGroup`
- Produces: `DashboardSidebarView(selection: Binding<DashboardSection>)`
- Produces: source-list sidebar with `List(selection:)` and `.listStyle(.sidebar)`

- [ ] **Step 1: Add the failing sidebar test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testDashboardSidebarUsesNativeSelectionAndKeepsDetailsOutOfSourceList() throws {
    let source = try appSource()
    let sidebar = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardSidebarView.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(sidebar.contains("struct DashboardSidebarView: View"))
    XCTAssertTrue(sidebar.contains("List(selection:"))
    XCTAssertTrue(sidebar.contains(".listStyle(.sidebar)"))
    XCTAssertTrue(sidebar.contains(".tag(section)"))
    XCTAssertFalse(sidebar.contains("DisclosureGroup"))
    XCTAssertFalse(sidebar.contains("FindingRow("))
    XCTAssertFalse(source.contains("private func sidebarRow("))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardSidebarUsesNativeSelectionAndKeepsDetailsOutOfSourceList
```

Expected: FAIL because `DashboardSidebarView.swift` does not exist and the current sidebar is hand-built.

- [ ] **Step 3: Create `DashboardSidebarView.swift`**

Create `Sources/MacDiskReclaimerApp/DashboardSidebarView.swift` with:

```swift
import SwiftUI

struct DashboardSidebarView: View {
    @Binding var selection: DashboardSection

    private var selectionBinding: Binding<DashboardSection?> {
        Binding<DashboardSection?>(
            get: { selection },
            set: { nextSelection in
                if let nextSelection {
                    selection = nextSelection
                }
            }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(DashboardSidebarGroup.allCases) { group in
                Section(group.rawValue) {
                    ForEach(sections(in: group)) { section in
                        DashboardSidebarRow(section: section)
                            .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Ryddi")
        .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
    }

    private func sections(in group: DashboardSidebarGroup) -> [DashboardSection] {
        DashboardSection.sidebarSections.filter { $0.sidebarGroup == group }
    }
}

private struct DashboardSidebarRow: View {
    let section: DashboardSection

    var body: some View {
        Label {
            Text(section.title)
                .lineLimit(1)
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 4: Replace the inline sidebar**

In `DashboardView`, replace:

```swift
NavigationSplitView {
    sidebar
} detail: {
```

with:

```swift
NavigationSplitView {
    DashboardSidebarView(selection: Binding(
        get: { selectedSection },
        set: { selectSection($0) }
    ))
} detail: {
```

Delete the old `private var sidebar` and `private func sidebarRow(...)` declarations from `DashboardView`.

- [ ] **Step 5: Keep queue details in the Review Queues detail view**

Do not add `model.queueSummaries`, `DisclosureGroup`, or `FindingRow` to `DashboardSidebarView`. The `ReviewQueuesView` detail workspace remains the queue evidence surface.

- [ ] **Step 6: Run the focused test and verify it passes**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardSidebarUsesNativeSelectionAndKeepsDetailsOutOfSourceList
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacDiskReclaimerApp/DashboardSidebarView.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "refactor: use native dashboard sidebar selection"
```

---

### Task 4: Scene Commands And Keyboard Shortcuts

**Files:**
- Create: `Sources/MacDiskReclaimerApp/DashboardCommands.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Produces: `struct DashboardCommandActions`
- Produces: `FocusedValues.dashboardCommandActions`
- Produces: `struct DashboardCommands: Commands`
- Consumes: `DashboardView.commandActions`
- Consumes: `DashboardSection`

- [ ] **Step 1: Add the failing commands test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testDashboardRegistersSceneCommandsAndFocusedActions() throws {
    let source = try appSource()
    let commands = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardCommands.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(commands.contains("struct DashboardCommandActions"))
    XCTAssertTrue(commands.contains("FocusedValueKey"))
    XCTAssertTrue(commands.contains("struct DashboardCommands: Commands"))
    XCTAssertTrue(commands.contains("CommandMenu(\"Ryddi\")"))
    XCTAssertTrue(commands.contains("keyboardShortcut(\"r\""))
    XCTAssertTrue(commands.contains("keyboardShortcut(\"d\", modifiers: [.command, .option])"))
    XCTAssertTrue(source.contains(".commands {\n            DashboardCommands()\n        }"))
    XCTAssertTrue(source.contains(".focusedSceneValue(\\.dashboardCommandActions"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardRegistersSceneCommandsAndFocusedActions
```

Expected: FAIL because there are no scene commands or focused dashboard actions.

- [ ] **Step 3: Create `DashboardCommands.swift`**

Create `Sources/MacDiskReclaimerApp/DashboardCommands.swift` with:

```swift
import SwiftUI

struct DashboardCommandActions {
    var canScan: Bool
    var canPlan: Bool
    var canDryRun: Bool
    var canExport: Bool
    var canReclaim: Bool
    var scan: () -> Void
    var buildPlan: () -> Void
    var dryRun: () -> Void
    var exportReport: () -> Void
    var exportRedactedReport: () -> Void
    var reclaim: () -> Void
    var openSection: (DashboardSection) -> Void
}

private struct DashboardCommandActionsKey: FocusedValueKey {
    typealias Value = DashboardCommandActions
}

extension FocusedValues {
    var dashboardCommandActions: DashboardCommandActions? {
        get { self[DashboardCommandActionsKey.self] }
        set { self[DashboardCommandActionsKey.self] = newValue }
    }
}

struct DashboardCommands: Commands {
    @FocusedValue(\.dashboardCommandActions) private var actions
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu("Ryddi") {
            Button("Scan") {
                actions?.scan()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(actions?.canScan != true)

            Button("Build Plan") {
                actions?.buildPlan()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(actions?.canPlan != true)

            Button("Dry Run") {
                actions?.dryRun()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(actions?.canDryRun != true)

            Divider()

            Button("Review Queues") {
                actions?.openSection(.queues)
            }
            .keyboardShortcut("1", modifiers: [.command])
            .disabled(actions == nil)

            Button("Audit History") {
                actions?.openSection(.audit)
            }
            .keyboardShortcut("2", modifiers: [.command])
            .disabled(actions == nil)

            Divider()

            Button("Export Report") {
                actions?.exportReport()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(actions?.canExport != true)

            Button("Export Redacted Report") {
                actions?.exportRedactedReport()
            }
            .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            .disabled(actions?.canExport != true)

            Divider()

            Button("Reclaim Selected") {
                actions?.reclaim()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(actions?.canReclaim != true)

            Divider()

            Button("Ryddi Settings") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
```

- [ ] **Step 4: Register scene commands**

In `MacDiskReclaimerApp`, add `.commands` to the `WindowGroup` scene:

```swift
WindowGroup("Ryddi", id: "dashboard") {
    DashboardView()
        .frame(
            minWidth: RyddiWindowLayout.minimumContentWidth,
            minHeight: RyddiWindowLayout.minimumContentHeight
        )
}
.defaultSize(width: RyddiWindowLayout.defaultContentWidth, height: RyddiWindowLayout.defaultContentHeight)
.windowResizability(.contentMinSize)
.commands {
    DashboardCommands()
}
```

- [ ] **Step 5: Export focused command actions from `DashboardView`**

Add this computed property inside `DashboardView`:

```swift
private var commandActions: DashboardCommandActions {
    DashboardCommandActions(
        canScan: !model.isWorking,
        canPlan: !model.findings.isEmpty && !model.isWorking,
        canDryRun: (model.plan != nil || !model.findings.isEmpty) && !model.isWorking,
        canExport: model.overview != nil && !model.findings.isEmpty && !model.isWorking,
        canReclaim: model.canReclaimSelected && selectedSection != .remoteTargets,
        scan: { Task { await model.scan() } },
        buildPlan: { Task { await model.buildPlan() } },
        dryRun: { Task { await model.runDryRun() } },
        exportReport: { Task { await model.exportEvidenceReport() } },
        exportRedactedReport: { Task { await model.exportEvidenceReport(pathStyle: .redacted, redactUserText: true) } },
        reclaim: { showingReclaimConfirmation = true },
        openSection: { selectSection($0) }
    )
}
```

Attach it to the `NavigationSplitView` chain:

```swift
.focusedSceneValue(\.dashboardCommandActions, commandActions)
```

- [ ] **Step 6: Run the focused test and verify it passes**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardRegistersSceneCommandsAndFocusedActions
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacDiskReclaimerApp/DashboardCommands.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "feat: add dashboard commands"
```

---

### Task 5: Native Settings With Persisted Preferences

**Files:**
- Create: `Sources/MacDiskReclaimerApp/DashboardSettingsView.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift` or `Sources/MacDiskReclaimerApp/DashboardView.swift` after Task 6
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Produces: `enum RyddiAppStorageKey`
- Produces: `struct DashboardSettingsView: View`
- Produces: `DashboardModel.applyStoredSettings(defaultScanPresetRaw:includeUserRulesByDefault:)`
- Consumes: `ScanScopePreset(rawValue:)`
- Consumes: `ReportPathStyle.allCases`

- [ ] **Step 1: Add the failing settings test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testSettingsAreNativePersistedAndReachable() throws {
    let source = try appSource()
    let settings = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardSettingsView.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(settings.contains("struct DashboardSettingsView: View"))
    XCTAssertTrue(settings.contains("@AppStorage(RyddiAppStorageKey.defaultScanPreset)"))
    XCTAssertTrue(settings.contains("@AppStorage(RyddiAppStorageKey.includeUserRulesByDefault)"))
    XCTAssertTrue(settings.contains("@AppStorage(RyddiAppStorageKey.defaultReportPathStyle)"))
    XCTAssertTrue(settings.contains("TabView"))
    XCTAssertTrue(settings.contains("Picker(\"Default scan mode\""))
    XCTAssertTrue(source.contains("Settings {\n            DashboardSettingsView()\n        }"))
    XCTAssertTrue(source.contains("applyStoredSettings(defaultScanPresetRaw:"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testSettingsAreNativePersistedAndReachable
```

Expected: FAIL because settings are static text and no persisted app settings exist.

- [ ] **Step 3: Create `DashboardSettingsView.swift`**

Create `Sources/MacDiskReclaimerApp/DashboardSettingsView.swift` with:

```swift
import SwiftUI
import ReclaimerCore

enum RyddiAppStorageKey {
    static let defaultScanPreset = "ryddi.defaultScanPreset"
    static let includeUserRulesByDefault = "ryddi.includeUserRulesByDefault"
    static let defaultReportPathStyle = "ryddi.defaultReportPathStyle"
    static let redactUserTextByDefault = "ryddi.redactUserTextByDefault"
}

struct DashboardSettingsView: View {
    @AppStorage(RyddiAppStorageKey.defaultScanPreset) private var defaultScanPresetRaw = ScanScopePreset.developer.rawValue
    @AppStorage(RyddiAppStorageKey.includeUserRulesByDefault) private var includeUserRulesByDefault = false
    @AppStorage(RyddiAppStorageKey.defaultReportPathStyle) private var defaultReportPathStyleRaw = ReportPathStyle.homeRelative.rawValue
    @AppStorage(RyddiAppStorageKey.redactUserTextByDefault) private var redactUserTextByDefault = false

    var body: some View {
        TabView {
            Form {
                Picker("Default scan mode", selection: $defaultScanPresetRaw) {
                    ForEach(ScanScopePreset.allCases) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }

                Toggle("Include user rules by default", isOn: $includeUserRulesByDefault)
            }
            .tabItem {
                Label("Scanning", systemImage: "magnifyingglass")
            }

            Form {
                Picker("Default report paths", selection: $defaultReportPathStyleRaw) {
                    ForEach(ReportPathStyle.allCases, id: \.rawValue) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }

                Toggle("Redact user-entered text by default", isOn: $redactUserTextByDefault)
            }
            .tabItem {
                Label("Privacy", systemImage: "hand.raised")
            }

            Form {
                Text("Scheduled work is report-only. Ryddi does not run unattended destructive cleanup.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tabItem {
                Label("Automation", systemImage: "calendar.badge.clock")
            }
        }
        .frame(width: 520, height: 300)
        .scenePadding()
    }
}
```

- [ ] **Step 4: Wire the Settings scene**

Replace:

```swift
Settings {
    SettingsView()
}
```

with:

```swift
Settings {
    DashboardSettingsView()
}
```

Delete the old `SettingsView` type.

- [ ] **Step 5: Apply settings once on app launch**

Add these properties to `DashboardView`:

```swift
@AppStorage(RyddiAppStorageKey.defaultScanPreset) private var defaultScanPresetRaw = ScanScopePreset.developer.rawValue
@AppStorage(RyddiAppStorageKey.includeUserRulesByDefault) private var includeUserRulesByDefault = false
```

Add this stored property to `DashboardModel`:

```swift
var hasAppliedStoredSettings = false
```

Add this method to `DashboardModel`:

```swift
func applyStoredSettings(defaultScanPresetRaw: String, includeUserRulesByDefault: Bool) {
    guard !hasAppliedStoredSettings else { return }
    hasAppliedStoredSettings = true

    if let defaultPreset = ScanScopePreset(rawValue: defaultScanPresetRaw) {
        scanPreset = defaultPreset
    }
    includeUserRulesInScans = includeUserRulesByDefault
    permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
}
```

Call it at the top of `DashboardView.onAppear`:

```swift
model.applyStoredSettings(
    defaultScanPresetRaw: defaultScanPresetRaw,
    includeUserRulesByDefault: includeUserRulesByDefault
)
```

- [ ] **Step 6: Run the focused test and verify it passes**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testSettingsAreNativePersistedAndReachable
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacDiskReclaimerApp/DashboardSettingsView.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "feat: add persisted app settings"
```

---

### Task 6: Split App Shell Files

**Files:**
- Create: `Sources/MacDiskReclaimerApp/RyddiWindowLayout.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Create: `Sources/MacDiskReclaimerApp/StatusMenuView.swift`
- Create: `Sources/MacDiskReclaimerApp/PathActions.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Produces: `MacDiskReclaimerApp.swift` with scene declarations only
- Produces: `DashboardView.swift` containing `DashboardView`
- Produces: `StatusMenuView.swift` containing `StatusMenuView` and `StatusMenuModel`
- Produces: `PathActions.swift` containing `PathActions`
- Produces: `RyddiWindowLayout.swift` containing `RyddiWindowLayout` and `DashboardResponsiveGrid`

- [ ] **Step 1: Add the failing file-boundary test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testAppEntrypointAndShellTypesAreSplitIntoFocusedFiles() throws {
    let appEntry = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift"),
        encoding: .utf8
    )
    let dashboard = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardView.swift"),
        encoding: .utf8
    )
    let status = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/StatusMenuView.swift"),
        encoding: .utf8
    )
    let pathActions = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/PathActions.swift"),
        encoding: .utf8
    )

    XCTAssertLessThan(appEntry.split(separator: "\n").count, 90)
    XCTAssertTrue(appEntry.contains("@main"))
    XCTAssertTrue(appEntry.contains("struct MacDiskReclaimerApp: App"))
    XCTAssertFalse(appEntry.contains("struct DashboardView"))
    XCTAssertFalse(appEntry.contains("final class DashboardModel"))
    XCTAssertTrue(dashboard.contains("struct DashboardView: View"))
    XCTAssertTrue(status.contains("struct StatusMenuView: View"))
    XCTAssertTrue(status.contains("final class StatusMenuModel"))
    XCTAssertTrue(pathActions.contains("enum PathActions"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppEntrypointAndShellTypesAreSplitIntoFocusedFiles
```

Expected: FAIL because those focused files do not all exist and the app entrypoint still owns many unrelated declarations.

- [ ] **Step 3: Move layout constants**

Move the existing `RyddiWindowLayout` and `DashboardResponsiveGrid` declarations from `MacDiskReclaimerApp.swift` into `Sources/MacDiskReclaimerApp/RyddiWindowLayout.swift`:

```swift
import SwiftUI

enum RyddiWindowLayout {
    static let minimumContentWidth: CGFloat = 1260
    static let minimumContentHeight: CGFloat = 760
    static let defaultContentWidth: CGFloat = 1480
    static let defaultContentHeight: CGFloat = 940
    static let topOffenderTableMinimumWidth: CGFloat = 1160
}

enum DashboardResponsiveGrid {
    static var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 320), spacing: 12, alignment: .top)]
    }

    static var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 118, maximum: 190), spacing: 10, alignment: .leading)]
    }
}
```

- [ ] **Step 4: Move `DashboardView`**

Move `DashboardView` from `MacDiskReclaimerApp.swift` into `Sources/MacDiskReclaimerApp/DashboardView.swift`. Keep its imports:

```swift
import SwiftUI
import ReclaimerCore
```

Do not move `OverviewView`, `ReviewQueuesView`, or other detail views in this task.

- [ ] **Step 5: Move status menu types**

Move `StatusMenuView` and `StatusMenuModel` from `MacDiskReclaimerApp.swift` into `Sources/MacDiskReclaimerApp/StatusMenuView.swift`. Keep these imports:

```swift
import SwiftUI
import ReclaimerCore
#if os(macOS)
import AppKit
#endif
```

- [ ] **Step 6: Move path actions**

Move `PathActions` from `MacDiskReclaimerApp.swift` into `Sources/MacDiskReclaimerApp/PathActions.swift`. Keep these imports:

```swift
import Foundation
#if os(macOS)
import AppKit
#endif
```

- [ ] **Step 7: Reduce `MacDiskReclaimerApp.swift` to scenes**

After the moves, `MacDiskReclaimerApp.swift` should have this shape:

```swift
import SwiftUI

@main
struct MacDiskReclaimerApp: App {
    @State private var statusModel = StatusMenuModel()

    var body: some Scene {
        WindowGroup("Ryddi", id: "dashboard") {
            DashboardView()
                .frame(
                    minWidth: RyddiWindowLayout.minimumContentWidth,
                    minHeight: RyddiWindowLayout.minimumContentHeight
                )
        }
        .defaultSize(width: RyddiWindowLayout.defaultContentWidth, height: RyddiWindowLayout.defaultContentHeight)
        .windowResizability(.contentMinSize)
        .commands {
            DashboardCommands()
        }

        MenuBarExtra {
            StatusMenuView(model: statusModel)
        } label: {
            Label(statusModel.menuTitle, systemImage: statusModel.symbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            DashboardSettingsView()
        }
    }
}
```

- [ ] **Step 8: Run the focused test and verify it passes**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppEntrypointAndShellTypesAreSplitIntoFocusedFiles
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/MacDiskReclaimerApp/RyddiWindowLayout.swift Sources/MacDiskReclaimerApp/DashboardView.swift Sources/MacDiskReclaimerApp/StatusMenuView.swift Sources/MacDiskReclaimerApp/PathActions.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "refactor: split app shell files"
```

---

### Task 7: Split DashboardModel By Responsibility

**Files:**
- Create: `Sources/MacDiskReclaimerApp/DashboardModel.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+Reviews.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+Remote.swift`
- Create: `Sources/MacDiskReclaimerApp/DashboardModel+Exports.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class DashboardModel` in `DashboardModel.swift`
- Produces: extensions grouped by behavior while preserving every existing public method signature used by views
- Consumes: existing `DashboardModel` methods and properties without changing caller APIs

- [ ] **Step 1: Add the failing model-boundary test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testDashboardModelIsSplitOutOfAppShellAndGroupedByResponsibility() throws {
    let appEntry = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift"),
        encoding: .utf8
    )
    let model = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardModel.swift"),
        encoding: .utf8
    )
    let scanPlan = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift"),
        encoding: .utf8
    )
    let audit = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift"),
        encoding: .utf8
    )
    let reviews = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardModel+Reviews.swift"),
        encoding: .utf8
    )
    let remote = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardModel+Remote.swift"),
        encoding: .utf8
    )
    let exports = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardModel+Exports.swift"),
        encoding: .utf8
    )

    XCTAssertFalse(appEntry.contains("final class DashboardModel"))
    XCTAssertTrue(model.contains("@Observable"))
    XCTAssertTrue(model.contains("final class DashboardModel"))
    XCTAssertTrue(scanPlan.contains("func scan() async"))
    XCTAssertTrue(scanPlan.contains("func reclaimSelected() async"))
    XCTAssertTrue(audit.contains("func loadAudit()"))
    XCTAssertTrue(audit.contains("func loadRecovery()"))
    XCTAssertTrue(reviews.contains("func reviewApps("))
    XCTAssertTrue(remote.contains("func probeRemoteTarget("))
    XCTAssertTrue(exports.contains("func exportEvidenceReport("))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardModelIsSplitOutOfAppShellAndGroupedByResponsibility
```

Expected: FAIL because the model still lives in the old app file and grouped extension files do not exist.

- [ ] **Step 3: Create `DashboardModel.swift` with the class and stored state**

Move the `@MainActor @Observable final class DashboardModel` declaration, all stored properties, computed properties, and small synchronous helpers that are pure state derivations into `DashboardModel.swift`.

Use this header:

```swift
import Foundation
import SwiftUI
import ReclaimerCore
```

Keep these method signatures in `DashboardModel.swift` if they are used by many views and are pure state reads:

```swift
func planItem(for findingID: Finding.ID) -> PlanItem?
func findings(in queueID: ReviewQueueID) -> [Finding]
func modelRecordSelection(_ queueID: ReviewQueueID) -> Bool
func nativePerformBlockReason(receipt: NativeToolExecutionReceipt, command: NativeToolCommand) -> String?
func applyStoredSettings(defaultScanPresetRaw: String, includeUserRulesByDefault: Bool)
```

- [ ] **Step 4: Create `DashboardModel+ScanPlan.swift`**

Move these existing methods unchanged except for the Task 1 session fix:

```swift
extension DashboardModel {
    func scan() async
    func buildPlan() async
    func runDryRun() async
    func reclaimSelected() async
    func refreshScanAfterReclaimPreservingExecutionSession() async
    func buildPlanWithoutChangingWorkingState() async
    func recordScanSession(updatedAt: Date)
    func recordPlanSession(_ plan: ReclaimPlan)
    func recordDryRunSession(_ receipt: ExecutionReceipt)
    func recordExecutionSession(_ receipt: ExecutionReceipt)
}
```

Use this header:

```swift
import Foundation
import ReclaimerCore
```

- [ ] **Step 5: Create `DashboardModel+AuditAndRecovery.swift`**

Move these existing methods:

```swift
extension DashboardModel {
    func loadSavedScopeSets()
    func loadAudit()
    func loadHolding()
    func loadRecovery()
    func refreshPermissions()
    func installSchedulePreview()
    func uninstallSchedule()
    func loadScopeTemplates()
    func saveCurrentScopeSet(named name: String)
    func deleteScopeSet(_ set: SavedScopeSet)
}
```

Use this header:

```swift
import Foundation
import ReclaimerCore
```

- [ ] **Step 6: Create `DashboardModel+Reviews.swift`**

Move these existing local review methods:

```swift
extension DashboardModel {
    func reviewTrash() async
    func reviewDownloads() async
    func reviewBrowsers() async
    func reviewPackages() async
    func reviewProjects() async
    func reviewDeviceBackups() async
    func reviewXcode() async
    func reviewContainers() async
    func reviewApps(includeSystemApps: Bool, includeOrphans: Bool) async
    func previewUninstallApp(_ group: AppReviewGroup) async
    func reviewAgents() async
}
```

Use this header:

```swift
import Foundation
import ReclaimerCore
```

- [ ] **Step 7: Create `DashboardModel+Remote.swift`**

Move these existing remote methods:

```swift
extension DashboardModel {
    func refreshRemoteTargets()
    func selectRemoteTarget(_ target: RemoteTargetReference)
    func probeRemoteTarget() async
    func scanRemoteTarget() async
    func exportRemoteReport(pathStyle: ReportPathStyle, redactUserText: Bool) async
    func exportRemoteGrowthReport(pathStyle: ReportPathStyle, redactUserText: Bool) async
    func exportRemoteDogfoodReport(pathStyle: ReportPathStyle, redactUserText: Bool) async
}
```

Use this header:

```swift
import Foundation
import ReclaimerCore
```

- [ ] **Step 8: Create `DashboardModel+Exports.swift`**

Move these existing export methods:

```swift
extension DashboardModel {
    func exportEvidenceReport(pathStyle: ReportPathStyle, redactUserText: Bool) async
    func exportPlanReport(_ plan: ReclaimPlan, pathStyle: ReportPathStyle) async
    func exportReceiptReport(_ receipt: ExecutionReceipt, pathStyle: ReportPathStyle) async
    func exportGrowthReport(pathStyle: ReportPathStyle, redactUserText: Bool) async
    func exportArchiveReview(pathStyle: ReportPathStyle, redactUserText: Bool) async
    func exportPolicy(pathStyle: ReportPathStyle) async
    func exportScopeSet(_ set: SavedScopeSet) async
}
```

Use this header:

```swift
import Foundation
import ReclaimerCore
```

- [ ] **Step 9: Run focused model-boundary test and build**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardModelIsSplitOutOfAppShellAndGroupedByResponsibility
swift build --scratch-path "$PWD/.build"
```

Expected: focused test PASS and build PASS. If the build exposes private-access errors after moving methods into extensions, keep the methods in the same type extension and lower only the smallest needed helper from `private` to `fileprivate` or internal.

- [ ] **Step 10: Commit**

```bash
git add Sources/MacDiskReclaimerApp/DashboardModel.swift Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift Sources/MacDiskReclaimerApp/DashboardModel+Reviews.swift Sources/MacDiskReclaimerApp/DashboardModel+Remote.swift Sources/MacDiskReclaimerApp/DashboardModel+Exports.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "refactor: split dashboard model"
```

---

### Task 8: Adaptive Apps And Leftovers Layout

**Files:**
- Modify: `Sources/MacDiskReclaimerApp/AppReviewViews.swift`
- Test: `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`

**Interfaces:**
- Produces: `AppReviewWorkspace` that uses `ViewThatFits(in: .horizontal)`
- Produces: `AppReviewFileTable` horizontal scroll containment for fixed-column rows
- Preserves: `AppReviewGroupRail`, `AppReviewDetailPanel`, `AppReviewFileHeader`, `AppReviewFileRow`

- [ ] **Step 1: Add the failing adaptive Apps layout test**

Append this test inside `MacDiskReclaimerAppLayoutTests`:

```swift
func testAppReviewWorkspaceHasAdaptiveFallbackAndTableScrollContainer() throws {
    let source = try String(
        contentsOf: repoRoot()
            .appendingPathComponent("Sources/MacDiskReclaimerApp/AppReviewViews.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
    XCTAssertTrue(source.contains("AppReviewFileTableScrollContainer"))
    XCTAssertTrue(source.contains("ScrollView(.horizontal)"))
    XCTAssertFalse(source.contains(".frame(width: 360)"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppReviewWorkspaceHasAdaptiveFallbackAndTableScrollContainer
```

Expected: FAIL because `AppReviewWorkspace` currently uses a fixed 360-point rail and no table scroll container.

- [ ] **Step 3: Replace fixed-width workspace layout**

Replace the `HStack` body inside `AppReviewWorkspace` with:

```swift
ViewThatFits(in: .horizontal) {
    HStack(alignment: .top, spacing: 16) {
        AppReviewGroupRail(
            groups: groups,
            selectedGroupID: activeGroupID,
            onSelect: { selectedGroupID = $0.id }
        )
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

        if let selectedGroup {
            AppReviewDetailPanel(
                group: selectedGroup,
                isWorking: isWorking,
                onPreviewUninstall: onPreviewUninstall
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    VStack(alignment: .leading, spacing: 16) {
        AppReviewGroupRail(
            groups: groups,
            selectedGroupID: activeGroupID,
            onSelect: { selectedGroupID = $0.id }
        )

        if let selectedGroup {
            AppReviewDetailPanel(
                group: selectedGroup,
                isWorking: isWorking,
                onPreviewUninstall: onPreviewUninstall
            )
        }
    }
}
```

- [ ] **Step 4: Add the table scroll container**

Wrap the file header and rows in a named scroll container:

```swift
struct AppReviewFileTableScrollContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(minWidth: 720, alignment: .leading)
        }
    }
}
```

Then change `AppReviewFileTable` to:

```swift
struct AppReviewFileTable: View {
    let items: [AppReviewItem]

    var body: some View {
        AppReviewFileTableScrollContainer {
            AppReviewFileHeader()
            ForEach(items) { item in
                AppReviewFileRow(item: item)
            }
        }
    }
}
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppReviewWorkspaceHasAdaptiveFallbackAndTableScrollContainer
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacDiskReclaimerApp/AppReviewViews.swift Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift
git commit -m "polish: adapt app review layout"
```

---

### Task 9: Final Verification And Evidence

**Files:**
- Modify: `docs/superpowers/plans/2026-07-09-ryddi-swiftui-best-practices-remediation.md` only if execution notes must be appended
- No production source edits in this task unless verification reveals a regression

**Interfaces:**
- Consumes: all previous tasks
- Produces: a verified local app shell remediation slice with conservative release claims

- [ ] **Step 1: Run disk guardrail**

Run:

```bash
df -h /System/Volumes/Data
```

Expected: available space is at least `50Gi`. Stop and report if it is below `50Gi`.

- [ ] **Step 2: Run focused layout tests**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests
```

Expected: PASS.

- [ ] **Step 3: Run full Swift tests**

Run:

```bash
swift test --scratch-path "$PWD/.build"
```

Expected: PASS.

- [ ] **Step 4: Run Swift build**

Run:

```bash
swift build --scratch-path "$PWD/.build"
```

Expected: PASS.

- [ ] **Step 5: Package an unsigned local preview**

Run:

```bash
Scripts/package-app.sh
```

Expected: `dist/Ryddi.app` exists. Do not call it signed or notarized unless signing env and notarization are actually run.

- [ ] **Step 6: Run release-check preview if disk still has headroom**

Run:

```bash
df -h /System/Volumes/Data
Scripts/release-check.sh
```

Expected: preview release check PASS. Manifest may identify unsigned local/debug state if signing env is absent.

- [ ] **Step 7: Run diff hygiene**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 8: Run temp hygiene**

Run:

```bash
du -sh /private/tmp/[Vv]ifty* 2>/dev/null || true
du -sh /private/tmp/[Rr]yddi* 2>/dev/null || true
```

Expected: no unexpected large stale temp dirs. Do not remove anything with active `lsof` handles.

- [ ] **Step 9: Manual app smoke**

Run:

```bash
open dist/Ryddi.app
```

Expected:
- Main window opens.
- Sidebar selection highlight is native.
- `Command-R` starts Scan when the app is focused.
- `Command-Option-D` starts Dry Run only when enabled.
- `Command-,` opens Settings.
- Review Queues and Apps & Leftovers remain usable at the app's minimum window size.
- No destructive remote action appears.

- [ ] **Step 10: Commit final verification notes if any repo docs were updated**

If no docs changed during verification, do not create an empty commit. If a short execution note was appended to this plan, run:

```bash
git add docs/superpowers/plans/2026-07-09-ryddi-swiftui-best-practices-remediation.md
git commit -m "docs: record swiftui remediation verification"
```

Expected: commit created only when there is a real repo diff.

---

## Self-Review

**Spec coverage**
- P1 app perform session gate: Task 1.
- Monolithic app shell: Tasks 6 and 7.
- Stringly typed navigation: Task 2.
- Native source-list sidebar: Task 3.
- Commands and keyboard shortcuts: Task 4.
- Real Settings scene with persisted preferences: Task 5.
- Fixed-width Apps layout risk: Task 8.
- Verification and conservative release claims: Task 9.

**Placeholder scan**
- This plan avoids undefined task markers and includes concrete file paths, tests, snippets, commands, and expected outcomes for each task.

**Type consistency**
- `DashboardSection`, `DashboardSidebarGroup`, `DashboardCommandActions`, `DashboardCommands`, `DashboardSettingsView`, and `RyddiAppStorageKey` are introduced before use.
- Existing view closures that still pass string section IDs are bridged through `DashboardSection.fromLegacyID(_:)` so child view APIs can remain stable in this slice.
- `DashboardModel.reclaimSelected()` keeps its existing public signature and changes only the executor configuration.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-09-ryddi-swiftui-best-practices-remediation.md`. Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using executing-plans, batch execution with checkpoints.

## Execution Results

- Disk headroom:
  - Pre-build guard: `df -h /System/Volumes/Data` exit `0`; available space `67Gi`.
  - Pre-release-check guard: `df -h /System/Volumes/Data` exit `0`; available space `68Gi`.
- Test gates on current HEAD `d68ccfc07e511d3e202fdecdff51b5afaedab069`:
  - Focused layout suite: `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests` exit `0`; `25` tests executed, `0` failures.
  - Focused permission regression suite: `MacDiskReclaimerAppPermissionAccessTests` `2/2` passed after the source-aggregation fix.
  - Full Swift suite: fresh `Scripts/release-check.sh` run executed `swift test --scratch-path .build`; `335` tests executed, `0` failures.
- Build/package/release-check:
  - `swift build --scratch-path "$PWD/.build"` exit `0`.
  - `Scripts/package-app.sh` exit `0`; produced `dist/Ryddi.app`.
  - `Scripts/release-check.sh` exit `0`; produced:
    - `dist/Ryddi-developer-preview.zip`
    - `dist/Ryddi-developer-preview.zip.sha256`
    - `dist/Ryddi-release-manifest.txt`
  - Release manifest trust state:
    - `artifact=Ryddi-developer-preview.zip`
    - `sha256=3bd2788c92fa5759c792b7d669f40dc346a7689e3090d64a626f5f55a0639201`
    - `codesign_verified=false`
    - `hardened_runtime=false`
    - `notarization_status=not requested`
    - `stapled=false`
    - `gatekeeper=not assessed`
  - Packaging script reported `CODESIGN_IDENTITY not set; app bundle left unsigned`, so this evidence is for an unsigned local developer preview only.
- Diff hygiene: `git diff --check` exit `0`.
- Temp hygiene:
  - No `/private/tmp/[Vv]ifty*` entries were present during the guarded check.
  - `/private/tmp/ryddi-task9-full.log` was `92K`.
  - `/private/tmp/ryddi-task9-red.log` was `8.0K`.
  - No temp paths were removed in this task.
- Live smoke from the packaged preview bundle:
  - Opened `dist/Ryddi.app` and directly observed the main `Ryddi` window with the native split-view sidebar and accent selection highlight.
  - Opened the native Settings window from the running preview via `Command-,` automation and returned to the main window.
  - Triggered one local scan from the visible UI and observed `Last Session Scanned Developer - 10 Jul 2026 at 0:04` with `3916` findings, `4,31 GB` auto-safe, `184 GB` needs review, and `Plan reclaim Zero KB`.
  - Built a plan from the visible UI and observed `Last Session Plan ready Developer - 10 Jul 2026 at 0:05` with `Plan reclaim 1,68 GB`.
  - Ran a dry run from the visible UI and observed `Last Session Dry run ready Developer - 10 Jul 2026 at 0:06` plus `Reclaim Ready`.
  - No remote execution was invoked. No destructive reclaim was invoked.
- Live smoke limitations:
  - `Command-R` scan and `Command-Option-D` dry-run shortcut behavior were not proven by direct observation. Automation-based keypress attempts left the visible state unchanged while the on-screen Scan and Dry Run controls worked, so shortcut behavior remains unobserved and should not be claimed as verified from this task.
  - Minimum-window usability for `Review Queues` and `Apps & Leftovers` was not re-verified in this continuation, so those layout claims remain covered by the focused test suite rather than fresh manual observation.
  - The preview quit path was exercised conservatively. Final process inspection showed only `/Applications/Ryddi.app/Contents/MacOS/Ryddi` still running; the installed copy was left untouched, and no extra quit was sent to it.
- Final task source range before this docs evidence commit: `edd5266a1665cd5aeb38739c4374b58c7cb9baeb..d68ccfc07e511d3e202fdecdff51b5afaedab069`.
