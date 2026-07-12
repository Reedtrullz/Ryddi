# Task 4 Report: Scene Commands And Keyboard Shortcuts

## What I implemented

- Added `DashboardCommandActions` and a `FocusedValues.dashboardCommandActions` bridge in `Sources/MacDiskReclaimerApp/DashboardCommands.swift`.
- Added `DashboardCommands: Commands` with a `CommandMenu("Ryddi")` that wires scene-level actions for scan, plan, dry run, export, redacted export, reclaim, section navigation, and settings.
- Registered the command set on the main `WindowGroup` scene in `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`.
- Added a `commandActions` computed property to `DashboardView` and exposed it with `.focusedSceneValue(\.dashboardCommandActions, commandActions)`.
- Added a layout test that pins the command surface and focused value wiring in `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`.

## RED evidence

- The first focused test build failed before the layout test could pass because the new `focusedSceneValue` modifier was accidentally placed outside the `DashboardView` body chain.
- Compiler evidence from the initial run included:
  - `expected declaration`
  - `extraneous '}' at top level`
  - `cannot find 'model' in scope`

## GREEN evidence

- Focused test passed after the brace fix:
  - `swift test --scratch-path "$PWD/.build" --filter MacDiskReclaimerAppLayoutTests/testDashboardRegistersSceneCommandsAndFocusedActions`
  - Result: `passed (0 failures)`
- Full build passed:
  - `swift build --scratch-path "$PWD/.build"`
  - Result: `Build complete!`

## Files changed

- `Sources/MacDiskReclaimerApp/DashboardCommands.swift`
  - `DashboardCommandActions` at lines 3-16
  - `FocusedValueKey` / `FocusedValues.dashboardCommandActions` at lines 18-27
  - `DashboardCommands` command menu and shortcuts at lines 29-97
- `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
  - scene `.commands { DashboardCommands() }` at lines 31-42
  - `.focusedSceneValue(\.dashboardCommandActions, commandActions)` at line 141
  - `commandActions` property at lines 249-264
- `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`
  - added `testDashboardRegistersSceneCommandsAndFocusedActions()` at lines 34-50

## Self-review

- The implementation follows the task brief closely and keeps the changes scoped to the three owned files.
- The command menu uses focused actions instead of reaching into the view model directly, which keeps the scene command layer decoupled from the dashboard view hierarchy.
- The `openSettings()` command compiled cleanly on this SDK, so no macOS 14 fallback was needed.

## Concerns

- No runtime UI smoke test was performed beyond compilation and the focused layout assertion, so keyboard routing is verified structurally rather than by live interaction.
- Task 5 still owns persisted settings; this task intentionally stops at scene commands and focused command actions.
