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
