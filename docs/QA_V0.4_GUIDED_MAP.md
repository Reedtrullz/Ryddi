# Ryddi v0.4 Guided Map QA

This checklist separates source/unit proof, packaged-app automation, and human assistive-technology review. A passing automated lane is not a signed/notarized release claim and does not replace a human VoiceOver pass.

## Product Contract

- The app opens without starting a scan.
- The main sidebar contains exactly Home, Explore, and History.
- `⌘R` starts a scan; `⌘1`, `⌘2`, and `⌘3` navigate those destinations.
- A successful scan produces a proportional map and accessible outline.
- Cancelling, failing, or superseding a scan leaves the last trustworthy map intact.
- Clicking or drilling into the map changes inspection only; it never selects cleanup.
- Cleanup Review opens with zero selected findings.
- Only explicit selected finding IDs reach planning.
- Move to Trash remains unavailable until the existing current dry-run and one-use authorization gates pass.
- The UI keeps allocated size, estimated reclaim, and observed reclaimed space distinct.

## Automated Commands

Run from the repository root:

```bash
df -h /System/Volumes/Data
swift test --scratch-path "$PWD/.build"
swift build -c release --scratch-path "$PWD/.build"
bash Tests/ScriptTests/release-trust-smoke.sh
bash Scripts/app-e2e-smoke.sh
bash Scripts/run-packaged-app-e2e.sh
git diff --check
```

The packaged Accessibility lane must use a disposable fixture and isolated audit, config, history, report, holding, and Guided Map roots. Its three responsive captures are:

- 820×620 minimum
- 1180×760 regular
- 1440×900 wide

## Manual Visual And Keyboard Review

- At 820×620, the sidebar, scan control, Home action, and primary map content remain reachable without clipping.
- Home contains one obvious primary action and at most three suggestions.
- Treemap rectangles are stable, non-overlapping, proportional, legible, and category-colored without relying on color alone.
- Breadcrumbs announce the current hierarchy; double-click drill-down has an equivalent outline path.
- Explore filters update both treemap and outline results.
- The inspector exposes Quick Look, Reveal in Finder, Copy Path, and Open Terminal only when valid.
- Cleanup Review clearly states that nothing is selected and does not visually imply otherwise.
- History distinguishes receipts/audits from Recovery.
- Advanced Settings remains discoverable through `⌘,`.
- Keyboard traversal reaches Home, Explore, History, Scan, treemap/outline controls, filters, inspector actions, cleanup selection, and Done.
- Focus is visible in light and dark appearances.

## Human VoiceOver Gate

With VoiceOver enabled, verify:

- Sidebar destinations, Scan, progress, and Cancel have useful names and states.
- Every treemap item has an equivalent outline row.
- Map/outline rows announce name, allocated size, category, and measurement state.
- Limited visibility is described as missing evidence, not as free space.
- Cleanup selection state and counts are announced.
- Check safely, confirmation, Move to Trash, result, and verification actions are announced in sequence.

Record the macOS version, Ryddi commit, appearance, window size, and any issues. Do not mark this gate complete from Accessibility API automation alone.

## Current Evidence

Fill this section only from commands run against the exact candidate commit:

- Unit/source-contract suite: passed, 718 tests with 1 intentional skip and 0 failures.
- Release build/package: passed; the local app is an unsigned developer preview.
- Release-trust script smoke: passed.
- Fixture smoke: passed with launch, screenshot, scan, plan, dry run, and protected-marker preservation.
- Packaged Accessibility E2E: passed through cancelled scan, completed scan, empty review, explicit selection, dry run, confirmation, Trash, receipt/result, and verification scan.
- Responsive containment: passed at 820×620, 1180×760, and 1440×900. Captures are in `dist/e2e-proof/`.
- Computer-assisted visual review: passed for the no-auto-scan launch state, exactly three destinations, current disk capacity, and one Home primary action.
- Human VoiceOver: not performed in automated implementation.
