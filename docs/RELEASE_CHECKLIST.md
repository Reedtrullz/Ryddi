# Ryddi Release Checklist

This project is intended for direct macOS distribution outside the Mac App Store. A public release should be explicit about whether it is an unsigned developer preview or a signed/notarized build.

## Developer Preview

- [ ] `Scripts/release-check.sh` passes and produces a zip, checksum, and release manifest.
- [ ] `swift test --scratch-path "$PWD/.build"` passes.
- [ ] `Scripts/package-app.sh` produces `dist/Ryddi.app`.
- [ ] `dist/Ryddi-developer-preview.zip` exists and preserves `Ryddi.app` as its parent item.
- [ ] `dist/Ryddi-developer-preview.zip.sha256` exists and matches the generated zip.
- [ ] `dist/Ryddi-release-manifest.txt` records bundle id, version, rules resource path, signing state, performed verification, and non-claims.
- [ ] App launches locally.
- [ ] `reclaimer status --json` reports disk pressure/free-space metadata without scanning content.
- [ ] `reclaimer scopes --preset general` shows General Mac roots and scan-scope non-claims.
- [ ] `reclaimer scopes saved add/list/show/export/import` works with a temporary `RYDDI_CONFIG_ROOT`, supports explicit replace import, and does not grant cleanup permission.
- [ ] `reclaimer scan --scope-set NAME --min-size 1 --json` scans saved roots while preserving normal safety classification and dry-run gates.
- [ ] `reclaimer rules` prints the bundled rule catalog with safety sections and non-claims.
- [ ] `reclaimer rules --json` includes `ruleVersion`, `sections`, and known never-touch rules such as `codex.credentials.never`.
- [ ] `reclaimer rules user preview RULES.json --json` validates local custom rules, rejects cleanup-granting rules, and does not mutate config.
- [ ] `reclaimer rules user import RULES.json --json` stores local user rules under a temporary `RYDDI_CONFIG_ROOT` without enabling them by default.
- [ ] `reclaimer rules --include-user-rules --json` shows user rule source/counts after import.
- [ ] `reclaimer scan --include-user-rules --path FIXTURE --min-size 1 --json` applies accepted user rules while keeping bundled never-touch protections effective.
- [ ] App Rule Catalog previews/imports/exports local user rule packs, reports validation issues before import, and app scans include user rules only when the User Rules toolbar toggle is on.
- [ ] App Scope Sets can save the current preset/saved scope, select it for scanning, import/export JSON, reveal the config file, and remove a saved set without mutating cleanup rules.
- [ ] `reclaimer permissions --json --path Tests` reports a permission coverage level, scope counts, recommended actions, and non-claims.
- [ ] `reclaimer permissions guide --path Tests --output permissions-guide.md` writes a first-run walkthrough with Full Disk Access steps, rescan/report-only commands, affected scopes, and non-claims.
- [ ] `reclaimer active --path Tests --json --save-audit` reports cleanup-relevant active-handle candidates, saves a local audit record, and does not quit processes or execute cleanup.
- [ ] `reclaimer overview --path Tests --limit 5 --sort reclaim --group safety` prints a bounded overview with grouped top-offender rows and conservative reclaim estimates.
- [ ] `reclaimer overview --path Tests --limit 5 --sort reclaim --group safety` includes owner/app/tool summaries.
- [ ] `reclaimer overview --json --path Tests --limit 5 --sort reclaim --group safety` includes bounded `mapNodes`, `ownerSummaries`, and `topOffenderTable`.
- [ ] `reclaimer queues --path Tests --limit 5 --json` reports all shared review queues, conservative reclaim estimates, sample rows, and queue non-claims without creating a cleanup plan.
- [ ] `reclaimer queues --path Tests --queue unknown --limit 5 --json` reports one queue with full queue accounting, bounded rows, guidance, and non-claims without creating a cleanup plan.
- [ ] `reclaimer large --path FIXTURE --min-size 1 --large-threshold 16000 --old-days 30 --json` reports large/old review rows, signal/category/safety summaries, and non-claims without selecting cleanup.
- [ ] `reclaimer drilldown --path FIXTURE --min-size 1 --max-depth 4 --tree-depth 4 --json` emits hierarchical `rootNodes`, bounded child rows, omitted-child summaries, and non-claims without creating a cleanup plan.
- [ ] `reclaimer report --path Tests --limit 5 --output REPORT.md` writes a local Markdown report with scan coverage, top findings, user policy, accounting notes, and non-claims without executing cleanup.
- [ ] `reclaimer report --path Tests --path-style redacted --redact-user-text --output REPORT.md` writes a local Markdown report without full local paths or user-entered policy reasons.
- [ ] `reclaimer plan --path Tests --output PLAN.md` writes a local Markdown reclaim plan report with selected actions, blocked/review items, safety buckets, estimates, and non-claims without executing cleanup.
- [ ] `reclaimer plans export --path-style redacted --output PLAN.md` exports a saved plan report with redacted action/review paths without mutating the saved plan.
- [ ] `reclaimer history record --path Tests --limit 5` saves a local-only snapshot.
- [ ] `reclaimer history list --limit 5` and `reclaimer history diff --group category --limit 5` read local-only snapshots.
- [ ] `reclaimer history report --output GROWTH.md` writes a local Markdown saved-snapshot comparison report with deltas, scan coverage, path privacy controls, and non-claims.
- [ ] `reclaimer duplicates --path FIXTURE --min-size 1 --json` groups same-content regular files, skips protected paths, and emits no cleanup plan.
- [ ] `reclaimer apps --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --json` reports installed app support files and orphan candidates without emitting a cleanup plan.
- [ ] `reclaimer apps uninstall-preview --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --output PREVIEW.md` writes a selected-app uninstall checklist where related files remain review-only and no deletion occurs.
- [ ] `reclaimer agents --path FIXTURE --min-size 1 --max-depth 4 --json` reports AI-agent storage buckets for cache, history, protected state, and quit-first data without emitting a cleanup plan.
- [ ] `reclaimer native --path FIXTURE --json --save-audit` emits preview-only native-tool receipts and saves a local audit record without executing native cleanup commands.
- [ ] `reclaimer execute --dry-run --path FIXTURE --save-audit` followed by `reclaimer receipts export --output RECEIPT.md` writes a local Markdown receipt report without rerunning cleanup.
- [ ] `reclaimer receipts export --path-style redacted --output RECEIPT.md` redacts receipt action paths and path-bearing messages without mutating the saved receipt.
- [ ] `reclaimer recovery --json` reports app-held, dry-run, skipped, Trash, native-tool, and direct-delete recovery states without mutating files.
- [ ] `reclaimer recovery restore HOLDING_ID --to DESTINATION` restores a disposable app-held fixture and refuses overwrite conflicts.
- [ ] `reclaimer containers --json --timeout 2 --save-audit` emits a read-only Docker/Colima inventory, saves a local audit record, and does not execute prune/delete/stop/reset commands.
- [ ] `reclaimer policy protect/exclude/list/remove/export/import` works with temporary `RYDDI_CONFIG_ROOT` values; protected paths are not selected for cleanup, excluded paths are absent from scan output, export writes a versioned JSON document, import merges by default, and `--replace` drops local-only rules.
- [ ] App Visual Map, Disk Drilldown, and Growth History render without changing reclaim gates.
- [ ] App Duplicate Review scans bounded roots and does not enable Reclaim or modify the dry-run plan.
- [ ] App Apps & Leftovers review scans bounded app roots and does not enable Reclaim or modify the dry-run plan.
- [ ] App AI Agent Storage review separates reclaimable cache from valuable history/protected state and does not enable Reclaim or modify the dry-run plan.
- [ ] App Recovery Center shows app-held restore rows separately from receipt-only guidance.
- [ ] App menu bar status item shows disk pressure and report-only scan controls without enabling cleanup actions.
- [ ] Manual GitHub Actions workflow `Release Preview Artifact` uploads the unsigned preview zip, checksum, and manifest when run.
- [ ] README states that the build is unsigned if `CODESIGN_IDENTITY` is unset.
- [ ] Release notes list non-claims: no notarization, no Full Disk Access guarantee, no real cleanup performed by packaging.

## Signed And Notarized Build

- [ ] `CODESIGN_IDENTITY` is set to a Developer ID Application certificate.
- [ ] `Scripts/package-app.sh` signs `dist/Ryddi.app` with Hardened Runtime.
- [ ] `Scripts/notarize-app.sh dist/Ryddi.app` completes successfully.
- [ ] `spctl --assess --type execute --verbose dist/Ryddi.app` accepts the app.
- [ ] `codesign --verify --deep --strict --verbose=2 dist/Ryddi.app` passes.
- [ ] GitHub release artifact and checksum are uploaded.

## Trust And Safety Notes

- [ ] `PRIVACY.md` is current.
- [ ] `docs/COMPETITIVE_RESEARCH.md` does not overclaim implemented features.
- [ ] CI is green on the release commit.
- [ ] Release notes say automation is report-first.
- [ ] Release notes say menu bar status is disk-pressure/report-only, not RAM cleaning or performance optimization.
- [ ] Release notes say duplicate review uses local hashes and does not automatically select or delete duplicates.
- [ ] Release notes say Apps & Leftovers is review-only and uninstall preview does not remove apps or delete app support files.
- [ ] Release notes say AI Agent Storage review is report-only and does not automatically delete sessions, memories, credentials, config, model state, profiles, or unknown agent data.
- [ ] Release notes say native-tool reports are preview-only and do not run Docker/Colima/Homebrew/package-manager cleanup commands automatically.
- [ ] Release notes say container inventory runs read-only inspection commands only.
- [ ] Release notes say user protections/exclusions are local path policy, exports can contain private paths/reasons, imports do not delete files or grant permissions, and policy data is not uploaded.
- [ ] Release notes say user rule packs are local, can contain private path fragments/app names/evidence text, are disabled by default unless explicitly included in CLI scans or app scans, cannot grant cleanup actions, and cannot downgrade bundled never-touch protections.
- [ ] Release notes say saved scope sets are local scan roots only, exports can contain private paths, and selecting a saved scope set does not grant cleanup permission.
- [ ] Release notes say permission coverage and walkthroughs are local path readability guidance and do not grant or prove global Full Disk Access.
- [ ] Release notes say active-handle reports can include process summaries and do not quit processes or execute cleanup.
- [ ] Release notes say evidence reports are local Markdown files that can include paths and do not execute cleanup.
- [ ] Release notes say disk drill-down is local scan metadata navigation, parent/child rows are not additive reclaim totals, and drill-down does not select cleanup.
- [ ] Release notes say growth reports compare saved local scan snapshots, can include paths, and do not prove exact current disk state or execute cleanup.
- [ ] Release notes say plan reports summarize proposed cleanup locally and do not execute cleanup or replace dry-run receipts.
- [ ] Release notes say receipt reports summarize saved receipts locally and do not rerun cleanup.
- [ ] Release notes say Recovery Center can restore only app-held items; Trash, native-tool, direct-delete, dry-run, skipped, and failed receipt rows are guidance, not guaranteed undo.
- [ ] Release notes say report redaction affects exports only; saved local audit JSON, plans, and receipts can still contain original local paths.
- [ ] Release notes say VM/container disks, browser profiles, GarageBand/Logic assets, Codex memories, and Codex sessions are not deleted automatically.
