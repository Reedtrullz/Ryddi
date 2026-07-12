# Task 8: Adaptive Apps And Leftovers Layout

## Status

Implemented from base commit `9e2a46852d55f751bce0f57971f3e4ea5e766a43`.

## Changes

- Added an adaptive `ViewThatFits(in: .horizontal)` workspace with the existing side-by-side rail/detail layout and a stacked fallback.
- Replaced the fixed `.frame(width: 360)` rail constraint with `minWidth: 280`, `idealWidth: 320`, and `maxWidth: 360`.
- Added `AppReviewFileTableScrollContainer` using `ScrollView(.horizontal)` and a `minWidth: 720` content frame for the fixed-column file table.
- Preserved `AppReviewGroupRail`, `AppReviewDetailPanel`, `AppReviewFileHeader`, `AppReviewFileRow`, review-only related-file behavior, and existing preview actions.

## TDD Evidence

- RED: `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppReviewWorkspaceHasAdaptiveFallbackAndTableScrollContainer` failed with 3 expected assertions before implementation.
- GREEN: The same focused test passed with 0 failures after implementation.

## Verification

- `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests`: 25 tests passed, 0 failures.
- `swift build --scratch-path "$PWD/.build"`: passed.
- `git diff --check`: passed.
- Changed files: `Sources/MacDiskReclaimerApp/AppReviewViews.swift` and `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`.

## Concerns

- No known concerns from the requested source-shape, layout test, build, and diff checks.
- Visual UI inspection was not part of the requested verification surface.

## Commit

Task commit subject: `polish: adapt app review layout`.

## Review Fix

Addressed the complete Task 8 review findings without changing other production files:

- Added `.frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)` to the horizontal detail panel so the first `ViewThatFits` candidate becomes ineligible when the rail and detail cannot fit together.
- Lifted `filterText` into `AppReviewWorkspace` and passed `$filterText` into both `AppReviewGroupRail` instances. `AppReviewGroupRail` now uses `@Binding`, so breakpoint changes preserve the search text.
- Strengthened `testAppReviewWorkspaceHasAdaptiveFallbackAndTableScrollContainer` to assert the concrete detail minimum width, workspace-owned state, binding declaration, and both rail bindings.

### TDD

- RED: `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppReviewWorkspaceHasAdaptiveFallbackAndTableScrollContainer` failed with 3 expected assertion failures for the missing width contract and shared filter ownership.
- GREEN: `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testAppReviewWorkspaceHasAdaptiveFallbackAndTableScrollContainer` passed: 1 test, 0 failures.

### Verification

- `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests`: 25 tests passed, 0 failures.
- `swift build --scratch-path "$PWD/.build"`: passed.
- `git diff --check`: passed.
