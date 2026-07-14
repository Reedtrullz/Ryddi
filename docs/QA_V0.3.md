# Ryddi v0.3.1 Human QA

Use this checklist on the exact unsigned preview or signed candidate being reviewed. Run `Scripts/app-e2e-smoke.sh` first; the automated smoke is disposable, fixture-scoped, and does not replace these visual and assistive checks.

Record the artifact filename, SHA-256, source commit, macOS version, Mac model, and whether the artifact is an unsigned preview or a signed candidate. Do not mark signing, notarization, stapling, or Gatekeeper acceptance unless the release manifest contains that proof.

## Manual Checks

- [ ] Fresh install opens Summary with one clear primary action and no stale scan evidence.
- [ ] Full Disk Access opens the correct System Settings pane from Permissions.
- [ ] Permission coverage changes only after access is granted, Ryddi is restarted when needed, and coverage is rechecked.
- [ ] Scan creates a current scan session for the selected scope.
- [ ] Scan shows observable progress and Cancel Scan; cancelling returns to idle, commits no findings later, and a following normal scan completes.
- [ ] A Review Queue row opens its finding detail and plan creation remains explicit.
- [ ] Dry run leaves protected browser profiles, Codex sessions, credentials, personal data, app bundles, and symlinks unchanged.
- [ ] Reclaim remains disabled with an explicit reason until the current plan has a clean matching dry run.
- [ ] Confirmed fixture Trash removes the completed finding row immediately, makes Verify Cleanup the primary action, and keeps Reclaim unavailable until fresh verification.
- [ ] The Homebrew action runs the actual cleanup preview first and does not enable perform from synthetic or stale evidence.
- [ ] Audit and scan-history retention dry runs mutate nothing; confirmed disposable-fixture retention moves only reviewed identity-matching known JSON to Finder Trash and preserves unknown files, directories, packages, symlinks, and replacements.
- [ ] An unreachable Remote Target fails without an interactive password or host-key prompt.
- [ ] Remote report export is redacted and Remote Targets report-only controls expose probe, scan, and export, never reclaim.
- [ ] The minimum window and a narrow supported window keep the sidebar, toolbar fallback, Summary metrics, and detail content usable without incoherent overlap.
- [ ] VoiceOver can find the primary Summary action and announces Scan, Plan, Dry Run, Reclaim, Permissions, Review Queues, and Remote Targets controls meaningfully.
- [ ] Keyboard task order works at 980×680: `⌘R` Scan, `⌥⌘P` Plan, `⌥⌘D` Dry Run, `⌥⌘R` exact-path confirmation, and `⌘1` Cleanup Flow; disabled commands remain unavailable until their evidence gate is current.
- [ ] Literal and hashed SSH `known_hosts` fixtures are recognized without weakening strict host-key checking or contacting a remote target.

## Required Screenshots

Capture only the Ryddi window. Keep usernames, local paths, hostnames, SSH aliases, and unrelated desktop content out of release evidence.

- [ ] `01-summary-before-scan.png`: Summary before scan with the primary action.
- [ ] `02-summary-after-scan.png`: Summary after a fixture or deliberately bounded scan.
- [ ] `03-permissions-degraded.png`: degraded coverage and exact next actions.
- [ ] `04-review-queue-detail.png`: selected queue, finding detail, and plan action.
- [ ] `05-audit-history-receipt.png`: dry-run or native preview receipt evidence.
- [ ] `06-remote-targets-report-only.png`: Remote Targets report-only probe, scan, export, and non-claim surfaces.

## Completion Evidence

- [ ] Automated fixture smoke output is attached to the review record.
- [ ] Packaged Accessibility evidence reports scan progress, cancellation-to-idle, no late cancelled result, normal scan completion, completed-row removal, Verify Cleanup, protected-fixture integrity, and cleanup of only the receipt-identified Trash fixture.
- [ ] Bundle metadata, embedded `Ryddi-build.json`, tag, manifest, zip basename, and checksum all identify `v0.3.1`, build `4`, and the same source commit.
- [ ] Required screenshots were reviewed at normal and narrow supported window sizes.
- [ ] Any failed or skipped check is recorded as a blocker rather than softened into a release claim.
- [ ] The candidate remains an unsigned preview unless the signed release gate independently passes.
