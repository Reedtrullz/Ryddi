# Ryddi macOS E2E Architecture And Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the packaged macOS app demonstrably usable across its primary cleanup flow, responsive window sizes, and assistive technologies while reducing the highest-risk SwiftUI and CLI monoliths.

**Architecture:** Introduce stable accessibility contracts and a two-tier app test harness: deterministic fixture-driven app flow in normal CI and Accessibility-driven packaged-app interaction for release proof. Extract feature views and CLI command families without changing core behavior. Add privacy-safe local `Logger` events and a real application icon through the package script.

**Tech Stack:** Swift 6, SwiftUI, AppKit Accessibility APIs, OSLog, SwiftPM, shell, GitHub Actions, macOS 14+.

## Global Constraints

- No telemetry upload; unified logs stay local and must not contain full paths, SSH targets, user text, or secrets.
- Refactors must be behavior-preserving and land separately from feature changes.
- The app must remain useful at its declared minimum window size; horizontal clipping is not an accepted responsive strategy.
- Release E2E must launch the packaged `.app`, not the raw SwiftPM executable.
- Screenshot evidence is mandatory for release proof and optional only for ordinary unit-test CI.
- App updater work remains out of scope.

---

## Task 1: Stable Accessibility And Flow Contract

**Files:**
- Create: `Sources/MacDiskReclaimerApp/AccessibilityIDs.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Modify: `Sources/MacDiskReclaimerApp/GuidedSummaryView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- Create: `Tests/ReclaimerCoreTests/AppFlowContractTests.swift`

**Interfaces:**

```swift
enum AccessibilityID {
    static let sidebar = "dashboard-sidebar"
    static let scan = "scan-button"
    static let cleanupFlow = "cleanup-flow"
    static func queue(_ id: ReviewQueueID) -> String { "queue-\(id.rawValue)" }
    static let planEligible = "plan-eligible-button"
    static let dryRun = "dry-run-button"
    static let reclaim = "reclaim-button"
    static let flowStatus = "cleanup-flow-status"
}
```

- [ ] Write a contract test enumerating every required identifier and expected enabled/disabled state at not-started, scanned, plan-ready, dry-run-ready, and reclaim-ready stages.
- [ ] Apply identifiers to controls and navigation destinations, not decorative containers.
- [ ] Give icon-only buttons localized accessibility labels and help text.
- [ ] Make progress/status changes announce through an accessibility live region or focused status element.
- [ ] Verify keyboard traversal reaches Scan, cleanup queues, Plan, Dry Run, and Reclaim in task order.
- [ ] Run focused/full tests.
- [ ] Commit: `test: define accessible cleanup flow contract`

## Task 2: Packaged-App E2E Harness

**Files:**
- Create: `Tests/AppE2E/RyddiAXHarness.swift`
- Create: `Scripts/run-packaged-app-e2e.sh`
- Modify: `Scripts/app-e2e-smoke.sh`
- Modify: `Scripts/package-app.sh`
- Modify: `.github/workflows/release-preview.yml`

**Interfaces:**

```text
Scripts/run-packaged-app-e2e.sh \
  --app dist/Ryddi.app \
  --fixture Tests/Fixtures/AppE2E \
  --output dist/e2e-proof
```

- [ ] Add a failing harness smoke that requires a valid `.app/Contents/Info.plist`, launches via `open -W -n`, finds the process by bundle ID, and times out with an AX hierarchy dump.
- [ ] Use `AXUIElement` to select the fixture scan mode, click Scan, wait for current-session completion, open Cleanup Flow, choose Safe Maintenance, click Plan, click Dry Run, and verify Reclaim readiness.
- [ ] When the recoverable Trash plan is implemented, add confirmation and protected-fixture assertions; until then assert Reclaim is disabled with an explicit reason.
- [ ] Capture a required window screenshot and machine-readable `e2e-result.json` with stage timings and assertion outcomes.
- [ ] Make release workflow fail if the screenshot, JSON proof, or protected-fixture hash is missing.
- [ ] Keep a deterministic in-app fixture mode for ordinary CI where Accessibility permission is unavailable; release publication requires the real AX lane on an approved runner.
- [ ] Run the harness twice to catch launch-state leakage.
- [ ] Commit: `test: exercise packaged app cleanup flow`

## Task 3: Responsive Window Acceptance

**Files:**
- Create: `Sources/MacDiskReclaimerApp/ResponsiveLayout.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Modify: `Sources/MacDiskReclaimerApp/GuidedSummaryView.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- Modify: `Tests/AppE2E/RyddiAXHarness.swift`

**Interfaces:**

```swift
enum DashboardLayoutClass: Equatable {
    case compact
    case regular
    case wide
    static func resolve(width: CGFloat) -> Self
}
```

- [ ] Add deterministic boundary tests for compact, regular, and wide widths.
- [ ] Define supported minimum window size in one place and apply it to the scene.
- [ ] Replace fixed multi-column metric grids with adaptive grids; collapse secondary metrics and table columns at compact widths.
- [ ] Convert the toolbar to keep Scan visible and move scope/template/report controls into menus as width decreases.
- [ ] In compact mode, use a single-column cleanup flow and a detail sheet/inspector instead of side-by-side queue/detail panes.
- [ ] Add E2E screenshots at minimum, 1280x800, and 1600x1000; fail on clipped primary controls or content extending outside the window frame.
- [ ] Verify sidebar collapse/restore and keyboard navigation at minimum size.
- [ ] Run focused/full tests and the three-size packaged-app harness.
- [ ] Commit: `fix: make dashboard responsive at supported sizes`

## Task 4: Targeted SwiftUI Decomposition

**Files:**
- Create: `Sources/MacDiskReclaimerApp/ReviewQueuesView.swift`
- Create: `Sources/MacDiskReclaimerApp/FindingDetailView.swift`
- Create: `Sources/MacDiskReclaimerApp/LargeOldReviewView.swift`
- Create: `Sources/MacDiskReclaimerApp/SharedFindingRows.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`

- [ ] Record a source inventory with `rg -n '^struct |^private struct |^extension ' Sources/MacDiskReclaimerApp/DashboardContentViews.swift` before moving code.
- [ ] Move `ReviewQueuesView` and its queue-only subviews/helpers into `ReviewQueuesView.swift` without changing access levels beyond what compilation requires.
- [ ] Move `FindingDetailView` and detail-only helpers into `FindingDetailView.swift`.
- [ ] Move `LargeOldReviewView` and archive/large-file presentation helpers into `LargeOldReviewView.swift`.
- [ ] Move only truly shared finding row/chip/action components into `SharedFindingRows.swift`; keep feature-specific components local.
- [ ] After each move, run `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors` and the related focused tests.
- [ ] Require `DashboardContentViews.swift` to fall below 4,000 lines in this slice; do not perform unrelated visual changes during the move commits.
- [ ] Commit each extraction separately with `refactor: extract ... views`.

## Task 5: Targeted CLI Decomposition

**Files:**
- Create: `Sources/reclaimer/ReviewCommands.swift`
- Create: `Sources/reclaimer/AuditCommands.swift`
- Create: `Sources/reclaimer/ReportCommands.swift`
- Modify: `Sources/reclaimer/ReclaimerCLI.swift`
- Create: `Tests/ReclaimerCoreTests/CLICompatibilityTests.swift`

- [ ] Capture `reclaimer help` and representative `--json` outputs as compatibility fixtures.
- [ ] Move review command dispatch/printing into `ReviewCommands`, audit summary/prune into `AuditCommands`, and report/export commands into `ReportCommands`.
- [ ] Keep argument parsing, exit codes, JSON schemas, and stderr behavior unchanged.
- [ ] Add tests that compare normalized old fixtures to new output for success, invalid option, and permission failure.
- [ ] Require `ReclaimerCLI.swift` to fall below 3,500 lines without introducing a generic command framework.
- [ ] Run all CLI smoke tests and full Swift tests after each extraction.
- [ ] Commit each command-family extraction separately.

## Task 6: Privacy-Safe Local Diagnostics

**Files:**
- Create: `Sources/MacDiskReclaimerApp/RyddiLog.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Modify: `Sources/MacDiskReclaimerApp/StatusMenuView.swift`
- Create: `Tests/ReclaimerCoreTests/DiagnosticRedactionTests.swift`

**Interfaces:**

```swift
enum RyddiLog {
    static let scan = Logger(subsystem: "com.reidar.ryddi", category: "scan")
    static let workflow = Logger(subsystem: "com.reidar.ryddi", category: "workflow")
    static let window = Logger(subsystem: "com.reidar.ryddi", category: "window")
}
```

- [ ] Write tests for a `DiagnosticMetadata` builder that exposes counts, durations, stage, preset, and error kind but never paths, aliases, usernames, rule text, or command output.
- [ ] Add signposts for scan, presentation-snapshot build, plan, dry run, Trash execution, and major navigation latency.
- [ ] Log stale-request rejection, permission-state transitions, and E2E checkpoints using privacy-safe enums/counts.
- [ ] Add an opt-in `Export Diagnostic Summary` that exports redacted app/version/timing/count data only; no unified log upload.
- [ ] Verify `rg -n 'Logger|os_signpost'` and inspect one local run with `log show --predicate 'subsystem == "com.reidar.ryddi"' --last 5m`.
- [ ] Commit: `chore: add local privacy-safe diagnostics`

## Task 7: Application Icon And Bundle Polish

**Files:**
- Create: `Assets/AppIcon.iconset/` source PNGs
- Create: `Assets/Ryddi.icns`
- Modify: `Scripts/package-app.sh`
- Modify: `docs/RELEASE_CHECKLIST.md`

- [ ] Create a restrained Ryddi icon that remains legible at 16, 32, 128, 256, 512, and 1024 pixels; avoid text in the icon.
- [ ] Generate `.icns` with `iconutil` and validate every required representation with `iconutil --convert iconset` round-trip.
- [ ] Copy `Ryddi.icns` into `Contents/Resources` and add `CFBundleIconFile=Ryddi` before signing.
- [ ] Add script assertions that the icon exists in the packaged app and `plutil` resolves the bundle key.
- [ ] Capture Finder, Dock, About, and app-switcher screenshots in release evidence.
- [ ] Commit: `design: add packaged Ryddi application icon`

## Task 8: Final macOS Quality Gate

**Files:**
- Modify: `docs/RELEASE_CHECKLIST.md`
- Modify: `README.md`
- Modify: `FEATURES.md`

- [ ] Document the primary flow as Scan, Review, Plan, Dry Run, Confirm, Trash, Recover.
- [ ] Document keyboard and VoiceOver acceptance, supported minimum size, local diagnostic privacy, and E2E limitations.
- [ ] Run `df -h /System/Volumes/Data`.
- [ ] Run `swift test --scratch-path "$PWD/.build"`.
- [ ] Run `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors`.
- [ ] Run `bash -n Scripts/*.sh` for touched scripts.
- [ ] Package the app and run the E2E harness at all three window sizes.
- [ ] Run `git diff --check` and the unsigned `Scripts/release-check.sh`.
- [ ] For release publication, require the signed/notarized gate from the separate release-trust plan.
- [ ] Commit: `docs: add macos quality and e2e release gates`

## Completion Criteria

- The packaged app completes the primary fixture flow through actual app controls with machine-readable and screenshot proof.
- Primary controls remain visible and operable at every supported window size.
- Accessibility identifiers, labels, keyboard traversal, and status announcements are stable.
- The largest SwiftUI and CLI monoliths shrink through behavior-preserving feature extraction.
- Local diagnostics explain latency and state changes without collecting private content.
- The packaged app carries a validated macOS icon.

## Execution Status (2026-07-12)

Automated implementation is complete through the unsigned release gate:

- Packaged AX drives Scan, Plan, Dry Run, exact-path confirmation, Trash, and recovery result; protected fixture hashes remain unchanged and the receipt-identified test Trash artifact is removed.
- Minimum (980×680), regular (1280×800), and wide (1600×1000) screenshots plus AX geometry containment checks pass.
- `DashboardContentViews.swift` is 3,987 lines and `ReclaimerCLI.swift` is 2,238 lines after behavior-preserving extraction commits.
- Privacy-safe diagnostics, signposts, coarse error/event metadata, local JSON export, and unified-log inspection pass without private payload fields.
- The generated Ryddi icon round-trips through `iconutil`, all ten iconset representations exist, and the packaged resource hash matches the source `.icns`.
- Full verification passed with 519 tests, 1 intentional skip, 0 failures; warnings-as-errors build, script syntax, packaged AX E2E, and unsigned `Scripts/release-check.sh` passed.

Manual release evidence remains intentionally open:

- Human VoiceOver traversal and announcements at 980×680.
- Human sidebar collapse/restore review at the minimum size.
- Finder, Dock, About, and app-switcher icon screenshots.
- Developer ID signing, notarization, stapling, Gatekeeper, and signed packaged-AX release proof.
