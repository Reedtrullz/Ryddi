# Task 5 Report: SwiftUI Remote Dogfood Cockpit

Date: 2026-07-07

## Changed files

- `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`

## Commands and results

- `df -h /System/Volumes/Data`
  - Result: 73 GiB available on `/System/Volumes/Data`; safe to proceed with build work.
- `swift build --scratch-path "$PWD/.build"`
  - Result: success. `Build complete! (15.22s)`

## Implementation summary

- Added dashboard model state for saved remote dogfood reports and the last exported dogfood markdown URL.
- Loaded saved remote dogfood reports from `AuditStore` during `loadAudit()` and hydrated the visible dogfood report from audit when the in-memory state was empty.
- Added `exportRemoteDogfoodReportFromAudit()` that builds redacted dogfood markdown from saved probe/scan audit evidence only and writes it under the report store root without reconnecting to SSH.
- Added a read-only `Dogfood Report` export button and a `Dogfood Evidence` section to the Remote Targets cockpit.
- Surfaced the last exported dogfood report path in the UI.

## Concerns

- The export action uses the most recent saved remote scan and only attaches probe/growth evidence for the same target when present. This matches the task brief, but the cockpit still does not let the user choose among multiple saved dogfood reports or targets.

## Fix implementation update

- Scoped the fix to `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`.
- Added `currentRemoteDogfoodReport` so the UI only renders dogfood evidence when it matches the current `remoteScanReport` target.
- Added `syncRemoteDogfoodReport()` and called it from `loadAudit()` and immediately after `scanRemoteTarget()` updates the in-memory scan, so stale dogfood evidence for another host is cleared or retargeted.
- Added a target label inside `Dogfood Evidence` so matching evidence is never shown without host context.

## Additional commands and results

- `git diff -- Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
  - Result: confirmed a narrow local patch limited to the remote dogfood section and dashboard model sync logic in `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`.
- `swift build --scratch-path "$PWD/.build"`
  - Result: success. `Build complete! (15.03s)`
- `git commit -m "fix: clear stale remote dogfood evidence"`
  - Result: success. Commit subject: `fix: clear stale remote dogfood evidence`.
