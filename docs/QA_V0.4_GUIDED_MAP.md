# Ryddi v0.4 Guided Map QA

This checklist separates source/unit proof, packaged-app automation, and human assistive-technology review. A passing automated lane is not a signed/notarized release claim and does not replace a human VoiceOver pass.

## Product Contract

- The app opens without starting a scan.
- The main sidebar contains exactly Home, Explore, and History.
- Explore contains Map, Outline, and Tools modes; Tools opens focused review workspaces without selecting cleanup.
- `⌘R` starts a scan; `⌘1`, `⌘2`, and `⌘3` navigate those destinations.
- A successful scan produces a proportional map and accessible outline.
- Scan progress explains that the previous trustworthy result remains visible; filesystem completion changes to result preparation instead of claiming the scan is finished early.
- The accepted map, suggestions, and coverage result become visible before durable history persistence finishes.
- Cancelling, failing, or superseding a scan leaves the last trustworthy map intact.
- Limited visibility presents direct Review Access and Set Up Cloud Review recovery actions.
- Home places the specific, bounded cleanup suggestions before the explanatory map.
- Each suggestion opens only its matching findings and cannot retain or bulk-select hidden findings.
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

With no explicit `RYDDI_E2E_APP_PATH`, the packaged Accessibility command first rebuilds `dist/Ryddi.app` from the current working tree. Release checks pass an explicit candidate so they exercise that exact bundle. The lane must use a disposable fixture and isolated audit, config, history, report, holding, and Guided Map roots. Its three responsive captures are:

- 820×620 minimum
- 1180×760 regular
- 1440×900 wide

## Manual Visual And Keyboard Review

- At 820×620, the sidebar, scan control, Home action, and primary map content remain reachable without clipping.
- Home contains one obvious primary action and at most three suggestions.
- Treemap rectangles are stable, non-overlapping, proportional, legible, and category-colored without relying on color alone.
- Treemap and outline share visible breadcrumbs; the outline uses an explicit Show contents action rather than making selection navigate unexpectedly.
- Explore filters update both treemap and outline results.
- Explore Tools exposes Apps, Cloud Footprint, Downloads, Browser Caches, Device Backups, Containers, and AI Agent Storage without requiring Settings.
- Cloud Footprint shows local progress, Stop, completion, and error feedback for discovery and metadata review.
- Cloud Footprint visibly explains provider-app setup for Dropbox, Google Drive, and MEGA and states that Ryddi does not sign in or organize remote files yet.
- Expandable treemap items expose a visible drill-in affordance, pointer help, and an accessibility Open action; Reduce Motion avoids animated repositioning.
- The inspector exposes Quick Look, Reveal in Finder, Copy Path, and Open Terminal only when valid.
- Cleanup Review clearly states that nothing is selected and does not visually imply otherwise.
- History distinguishes receipts/audits from Recovery.
- Advanced Settings remains discoverable through `⌘,`.
- Keyboard traversal reaches Home, Explore, History, Scan, treemap/outline controls, filters, inspector actions, cleanup selection, and Done.
- Focus is visible in light and dark appearances.
- Status changes are announced without stealing focus, and Reduce Motion avoids animated map or outline repositioning.

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

Fill this section only from commands run against the exact candidate working tree or commit:

- Evidence boundary: local source-dirty working tree on 18 July 2026; not a committed, installed, signed, notarized, or published candidate.
- Unit/source-contract suite: passed, 758 tests with 1 intentional skip and 0 failures.
- Release build/package: passed; the local app is an unsigned developer preview.
- Release-trust script smoke: passed.
- Fixture smoke: passed with launch, screenshot, scan, plan, dry run, and protected-marker preservation.
- Packaged Accessibility E2E: passed from a freshly rebuilt source-dirty bundle through visible scan status, cancelled scan, visible completed-scan result, a Safe maintenance review containing only its matching findings and explicitly reporting `0 selected`, Explore Tools, visible Cloud Footprint setup guide, an empty broad cleanup review, explicit selection, dry run, confirmation, Trash, receipt/result, and verification scan.
- Responsive containment: passed at 820×620, 1180×760, and 1440×900. Captures are in `dist/e2e-proof/`.
- Computer-assisted visual review: passed for action-first Home hierarchy, scoped cleanup review, Explore Tools, Cloud Footprint, responsive Home, explicit outline navigation, visible treemap drill-in, and clickable suggestion cards. Captures are in `dist/e2e-proof/`.
- Anti sidecar review: Claude Opus 4.6 completed a broad working-tree review followed by a narrowed full-file review of the scan, review-selection, cloud-discovery, cloud-inventory, dashboard, and Accessibility harness paths. Local verification accepted the scoped-selection, cancellation, bounded top-N, and harness-performance findings; it rejected findings that conflicted with the user-started cloud contract or current actor/idempotency behavior. Compilation and packaged Accessibility testing also caught and reversed two sidecar-proposed regressions before this evidence was recorded.
- Human VoiceOver: not performed in automated implementation.
