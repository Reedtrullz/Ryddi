# Task 6 Report: Split App Shell Files

Date: 2026-07-09 22:05 CEST

## Status

Complete. `MacDiskReclaimerApp.swift` is reduced to scene declarations only and is under the 90-line acceptance threshold.

## RED/GREEN/build evidence

- RED: `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppEntrypointAndShellTypesAreSplitIntoFocusedFiles`
  - Result: exit 1. Build completed, then the focused test failed because `Sources/MacDiskReclaimerApp/DashboardView.swift` did not exist.
- GREEN: `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppEntrypointAndShellTypesAreSplitIntoFocusedFiles`
  - Result: exit 0. Executed 1 test, 0 failures.
- Layout slice: `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests`
  - First result: exit 1. Executed 24 tests, 1 failure in `testDashboardNavigationUsesTypedSectionsAndSceneStorage` because the helper still sliced the old monolithic app source from `DashboardView` to `OverviewView`.
  - Fix: changed `dashboardViewSource()` to read `Sources/MacDiskReclaimerApp/DashboardView.swift` directly; assertions were unchanged.
  - Final result: exit 0. Executed 24 tests, 0 failures.
- Build: `swift build --scratch-path "$PWD/.build"`
  - Result: exit 0. Build complete.
- Whitespace: `git diff --check`
  - Result: exit 0.

## Line counts after split

```text
32    Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift
19    Sources/MacDiskReclaimerApp/RyddiWindowLayout.swift
245   Sources/MacDiskReclaimerApp/DashboardView.swift
6672  Sources/MacDiskReclaimerApp/DashboardContentViews.swift
67    Sources/MacDiskReclaimerApp/PathActions.swift
182   Sources/MacDiskReclaimerApp/StatusMenuView.swift
```

## Files moved

- `RyddiWindowLayout` and `DashboardResponsiveGrid` moved to `Sources/MacDiskReclaimerApp/RyddiWindowLayout.swift`.
- `DashboardView` moved to `Sources/MacDiskReclaimerApp/DashboardView.swift`.
- The untouched remaining detail/support-view declarations moved to `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`.
- `PathActions` moved to `Sources/MacDiskReclaimerApp/PathActions.swift`.
- `StatusMenuView`, `DiskPressureBadge`, and `StatusMenuModel` moved to `Sources/MacDiskReclaimerApp/StatusMenuView.swift`.

## Access/import changes

- `RyddiWindowLayout` changed from `private enum` to module-internal `enum` so `MacDiskReclaimerApp.swift` can reference it after the split.
- `MacDiskReclaimerApp.swift` now imports only `SwiftUI`.
- `RyddiWindowLayout.swift` imports `SwiftUI`.
- `DashboardView.swift` imports `SwiftUI` and `ReclaimerCore`.
- `DashboardContentViews.swift` imports `SwiftUI`, `ReclaimerCore`, `UniformTypeIdentifiers`, and macOS-only `AppKit`.
- `PathActions.swift` imports `Foundation` and macOS-only `AppKit`.
- `StatusMenuView.swift` imports `SwiftUI`, `ReclaimerCore`, and macOS-only `AppKit`.

## Self-review

- Mechanical comparison against `HEAD:Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift` found `DashboardView`, `DashboardContentViews`, `PathActions`, and `StatusMenuView` declaration text identical after extraction.
- `RyddiWindowLayout` was identical except for the required access widening from `private` to module-internal.
- No `DashboardModel` files or model behavior were edited.
- Existing tests still cover Task 4 focused command actions and Task 5 persisted export settings through the app target source aggregate.

## Concerns

- Full `swift test` was not run; verification used the requested focused boundary test, layout test slice, `swift build`, and diff checks.
