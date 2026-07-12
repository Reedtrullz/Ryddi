# Ryddi Release Checklist

This project is intended for direct macOS distribution outside the Mac App Store. A public release must be explicit about whether it is an unsigned developer preview or a signed/notarized build. `v0.3.0` is the current trust-release target and must not be published unless the signed gate passes. `v0.2.0` remains historical release documentation only.

Human review follows [QA_V0.3.md](QA_V0.3.md).

## Developer Preview

- [ ] `Scripts/release-check.sh` passes and produces a zip, checksum, and release manifest.
- [ ] `swift test --scratch-path "$PWD/.build"` passes.
- [ ] `Scripts/package-app.sh` produces `dist/Ryddi.app`.
- [ ] `Scripts/app-e2e-smoke.sh` launches the packaged app with a disposable temporary fixture, proves scan/plan/dry-run and app-uninstall dry-run, and preserves protected browser, Codex, symlink, and app-bundle fixtures without Full Disk Access.
- [ ] `RYDDI_E2E_REQUIRE_SCREENSHOT=1 Scripts/app-e2e-smoke.sh` captures a non-empty Ryddi-window-only screenshot on the manual QA Mac.
- [ ] `Scripts/run-packaged-app-e2e.sh` passes from an Accessibility-approved Mac account, drives Scan through confirmed Trash, preserves protected fixtures, captures three window sizes, and reports `trashArtifactCleaned=true`.
- [ ] `Export Diagnostic Summary` writes a local JSON file containing typed timing/count metadata only; inspect `log show --info --predicate 'subsystem == "com.reidar.ryddi"' --last 5m` and confirm no private path or command payload appears.
- [ ] `dist/Ryddi-developer-preview.zip` exists and preserves `Ryddi.app` as its parent item.
- [ ] `dist/Ryddi-developer-preview.zip.sha256` exists and matches the generated zip.
- [ ] `dist/Ryddi-release-manifest.txt` records bundle id, version, rules resource path, signing state, performed verification, and non-claims.
- [ ] App launches locally.
- [ ] The required Summary, Permissions, Review Queue, Audit History, and Remote Targets screenshots and VoiceOver checks in `docs/QA_V0.3.md` are complete.
- [ ] `reclaimer status --json` reports disk pressure/free-space metadata without scanning content.
- [ ] `reclaimer scopes --preset general` shows General Mac roots and scan-scope non-claims.
- [ ] `reclaimer scopes templates list/show/save` exposes built-in guided templates, can save a template into a temporary `RYDDI_CONFIG_ROOT`, and does not grant cleanup permission.
- [ ] `reclaimer scan --template weekly-general --min-size 1 --json` scans template roots while preserving normal safety classification and dry-run gates.
- [ ] `reclaimer scopes saved add/list/show/export/import` works with a temporary `RYDDI_CONFIG_ROOT`, supports explicit replace import, and does not grant cleanup permission.
- [ ] `reclaimer scan --scope-set NAME --min-size 1 --json` scans saved roots while preserving normal safety classification and dry-run gates.
- [ ] `reclaimer rules` prints the bundled rule catalog with safety sections and non-claims.
- [ ] `reclaimer rules --json` includes `ruleVersion`, `sections`, and known never-touch rules such as `codex.credentials.never`.
- [ ] `reclaimer rules user preview RULES.json --json` validates local custom rules, rejects cleanup-granting rules, and does not mutate config.
- [ ] `reclaimer rules user import RULES.json --json` stores local user rules under a temporary `RYDDI_CONFIG_ROOT` without enabling them by default.
- [ ] `reclaimer rules --include-user-rules --json` shows user rule source/counts after import.
- [ ] `reclaimer scan --include-user-rules --path FIXTURE --min-size 1 --json` applies accepted user rules while keeping bundled never-touch protections effective.
- [ ] App Rule Catalog previews/imports/exports local user rule packs, reports validation issues before import, and app scans include user rules only when the User Rules toolbar toggle is on.
- [ ] App Scope Sets can use built-in templates, save a template copy, save the current preset/template/saved scope, select it for scanning, import/export JSON, reveal the config file, and remove a saved set without mutating cleanup rules.
- [ ] `reclaimer permissions --json --path Tests` reports a permission coverage level, scope counts, recommended actions, and non-claims.
- [ ] `reclaimer permissions guide --path Tests --output permissions-guide.md` writes a first-run walkthrough with Full Disk Access steps, rescan/report-only commands, affected scopes, and non-claims.
- [ ] `reclaimer active --path Tests --json --save-audit` reports cleanup-relevant active-handle candidates, saves a local audit record, and does not quit processes or execute cleanup.
- [ ] `reclaimer overview --path Tests --limit 5 --sort reclaim --group safety` prints a bounded overview with grouped top-offender rows and conservative reclaim estimates.
- [ ] `reclaimer overview --path Tests --limit 5 --sort reclaim --group safety` includes owner/app/tool summaries.
- [ ] `reclaimer overview --json --path Tests --limit 5 --sort reclaim --group safety` includes bounded `mapNodes`, `ownerSummaries`, and `topOffenderTable`.
- [ ] `reclaimer trust --json --path Tests` reports trust readiness, scan coverage, latest local audit state, next-action counts, release trust state, and non-claims without executing cleanup.
- [ ] `reclaimer dogfood --path Tests --path-style redacted --output DOGFOOD.md` writes a report with disk status, scan coverage, top owners, queues, selected dry-run summary, active-handle summary, protected buckets, and non-claims without full paths or cleanup.
- [ ] `reclaimer queues --path Tests --limit 5 --json` reports all shared review queues, conservative reclaim estimates, sample rows, and queue non-claims without creating a cleanup plan.
- [ ] `reclaimer queues --path Tests --queue unknown --limit 5 --json` reports one queue with full queue accounting, bounded rows, guidance, and non-claims without creating a cleanup plan.
- [ ] `reclaimer explain FIXTURE --json --min-size 1` reports what/why/risk/action/recovery/condition/next-step sections and non-claims without executing cleanup.
- [ ] `reclaimer large --path FIXTURE --min-size 1 --large-threshold 16000 --old-days 30 --json` reports large/old review rows, signal/category/safety summaries, and non-claims without selecting cleanup.
- [ ] `reclaimer archive --path FIXTURE --min-size 1 --large-threshold 16000 --old-days 30 --json` reports archive-review recommendations and non-claims without compressing, moving, Trashing, deleting, or selecting cleanup.
- [ ] `reclaimer archive --path FIXTURE --path-style redacted --output ARCHIVE.md` writes a local Markdown archive checklist without full local paths and without executing cleanup.
- [ ] `reclaimer drilldown --path FIXTURE --min-size 1 --max-depth 4 --tree-depth 4 --json` emits hierarchical `rootNodes`, bounded child rows, omitted-child summaries, and non-claims without creating a cleanup plan.
- [ ] `reclaimer report --path Tests --limit 5 --output REPORT.md` writes a local Markdown report with scan coverage, top findings, user policy, accounting notes, and non-claims without executing cleanup.
- [ ] `reclaimer report --path Tests --path-style redacted --redact-user-text --output REPORT.md` writes a local Markdown report without full local paths or user-entered policy reasons.
- [ ] `reclaimer plan --path Tests --output PLAN.md` writes a local Markdown reclaim plan report with selected actions, blocked/review items, safety buckets, estimates, and non-claims without executing cleanup.
- [ ] `reclaimer plans export --path-style redacted --output PLAN.md` exports a saved plan report with redacted action/review paths without mutating the saved plan.
- [ ] `reclaimer history record --path Tests --limit 5` saves a local-only snapshot.
- [ ] `reclaimer history list --limit 5` and `reclaimer history diff --group category --limit 5` read local-only snapshots.
- [ ] `reclaimer history report --output GROWTH.md` writes a local Markdown saved-snapshot comparison report with deltas, scan coverage, path privacy controls, and non-claims.
- [ ] `reclaimer duplicates --path FIXTURE --min-size 1 --json` groups same-content regular files, skips protected paths, and emits no cleanup plan.
- [ ] `reclaimer downloads --path FIXTURE/Downloads --json --save-audit` reports old downloads, installers, archives, workflow buckets, workflow steps, and largest items, saves a local audit record, and does not move, archive, Trash, or delete files.
- [ ] `reclaimer browsers --path FIXTURE/Library/Caches/Google/Chrome --home FIXTURE --json --save-audit` reports browser cache roots, protected profile roots, advisory browser runtime status, and largest cache items, saves a local audit record, and does not quit browsers or mutate browser cache/profile files.
- [ ] `reclaimer packages --home FIXTURE --json --save-audit` reports package-manager cache roots, protected config/auth paths, largest cache items, native cleanup guidance, saves a local audit record, and does not mutate package-manager files.
- [ ] `reclaimer projects policy skip-review FIXTURE/Projects/SkippedWeb --reason "release smoke"` saves local per-project policy, `projects policy export/import` round-trips it, and `reclaimer projects --path FIXTURE/Projects --json --include-vcs-status --save-audit` reports project-local dependency/build artifact folders, protected project roots, ecosystem/kind/tool/script/script-risk/workspace/VCS/policy summaries, skipped-by-policy projects, package names, bounded/redacted package.json script command previews, detected package-manager/script command hints, workspace-inherited package-manager hints, command working directories, workspace package selectors, saves a local audit record, and does not mutate source, manifests, lockfiles, env files, dependencies, build outputs, credentials, IDE settings, workspace metadata, generated code, local editable installs, unknown project state, or execute project scripts.
- [ ] `reclaimer xcode --home FIXTURE --json --save-audit` reports Xcode cache, archive, DeviceSupport, simulator, runtime, log, preview, and protected developer-state roots, saves a local audit record, and does not mutate Xcode files.
- [ ] `reclaimer device-backups --home FIXTURE --json --save-audit` reports MobileSync backup size, age, encryption, parsed/missing metadata, Apple/Finder guidance, saves a local audit record, and does not mutate backups.
- [ ] `reclaimer trash --path FIXTURE/.Trash --json --save-audit` reports Trash size/largest items, saves a local audit record, and does not empty, restore, move, or delete files.
- [ ] `reclaimer apps --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --json` reports installed app support files and orphan candidates without emitting a cleanup plan.
- [ ] `reclaimer apps uninstall-preview --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --output PREVIEW.md` writes a selected-app uninstall checklist where related files remain review-only and no deletion occurs.
- [ ] `reclaimer apps uninstall --dry-run --save-audit --app FIXTURE.app --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --json` writes evidence for manual Finder removal while related files remain untouched.
- [ ] `reclaimer apps uninstall --yes ...` is rejected and preserves the selected app bundle.
- [ ] `reclaimer agents --path FIXTURE --min-size 1 --max-depth 4 --json` reports AI-agent storage buckets for cache, history, protected state, and quit-first data without emitting a cleanup plan.
- [ ] `reclaimer agents retention --path FIXTURE --profile balanced --min-size 1 --max-depth 4 --json` reports cleanup-plan, compression-review, keep, and protect recommendations without deleting, compressing, moving, or modifying agent files.
- [ ] `reclaimer native --path FIXTURE --json --save-audit` emits native-tool preview receipts and saves a local audit record without executing native cleanup commands.
- [ ] `reclaimer native run --command-id brew.preview --path FIXTURE --dry-run --json --save-audit` runs only the exact bounded Homebrew preview command and captures its output in a native command execution receipt.
- [ ] `reclaimer native homebrew cleanup --dry-run --finding-path FIXTURE/Library/Caches/Homebrew --json --save-audit` saves Homebrew's actual preview output as an exportable native command receipt.
- [ ] `reclaimer native receipts list --json` and `reclaimer native receipts export --path-style redacted --output RECEIPT.md` retrieve saved native command receipts without rerunning native tools.
- [ ] `reclaimer native run --command-id brew.cleanup --finding-path FIXTURE/Library/Caches/Homebrew --path FIXTURE --yes --save-audit` runs a fresh preview and consumes its same-process capability before the exact cleanup invocation; saved receipts cannot authorize a later run.
- [ ] `reclaimer execute --dry-run --path FIXTURE --save-audit` followed by `reclaimer receipts export --output RECEIPT.md` writes a local Markdown receipt report without rerunning cleanup.
- [ ] `reclaimer receipts export --path-style redacted --output RECEIPT.md` redacts receipt action paths and path-bearing messages without mutating the saved receipt.
- [ ] `reclaimer recovery --json` reports holding records as manual Finder review, plus dry-run, skipped, Trash, and native-tool recovery states without mutating files.
- [ ] `reclaimer recovery restore HOLDING_ID --to DESTINATION` rejects automatic moves and preserves the disposable held fixture for manual Finder review.
- [ ] `reclaimer containers --json --timeout 2 --save-audit` emits a read-only Docker/Colima inventory, saves a local audit record, and does not execute prune/delete/stop/reset commands.
- [ ] `reclaimer remote history list/diff/report` reads disposable saved reachable remote scan audit records, writes a redacted remote growth Markdown report, excludes unreachable scans from default comparisons, and does not connect to or mutate a server.
- [ ] `reclaimer remote dogfood --from-audit` writes redacted Markdown from disposable saved remote audit records and does not connect to or mutate a server.
- [ ] `reclaimer issue package --path-style redacted --include-remote --output DIR` writes manifest, report, non-claims, local summary, and optional redacted remote summary without copying raw SSH config, private keys, tokens, or arbitrary audit JSON.
- [ ] `reclaimer policy protect/exclude/list/remove/export/import` works with temporary `RYDDI_CONFIG_ROOT` values; protected paths are not selected for cleanup, excluded paths are absent from scan output, export writes a versioned JSON document, import merges by default, and `--replace` drops local-only rules.
- [ ] App Visual Map, Disk Drilldown, and Growth History render without changing reclaim gates.
- [ ] App Duplicate Review scans bounded roots and does not enable Reclaim or modify the dry-run plan.
- [ ] App Apps & Leftovers review scans bounded app roots and does not enable Reclaim or modify the dry-run plan.
- [ ] App AI Agent Storage review separates reclaimable cache from valuable history/protected state and does not enable Reclaim or modify the dry-run plan.
- [ ] App Recovery Center shows holding records separately from receipt guidance without exposing automatic restore or expiry actions.
- [ ] App menu bar status item shows disk pressure and report-only scan controls without enabling cleanup actions.
- [ ] Manual GitHub Actions workflow `Release Preview Artifact` uploads the unsigned preview zip, checksum, and manifest when run.
- [ ] README states that the build is unsigned if `CODESIGN_IDENTITY` is unset.
- [ ] Release notes list non-claims: no notarization, no Full Disk Access guarantee, no real cleanup performed by packaging.

## Signed And Notarized Build

- [ ] `Scripts/release-signing-doctor.sh` reports the Developer ID Application identity and notary credential path are ready without printing password values.
- [ ] `RYDDI_RELEASE_SIGNING=required RYDDI_REQUIRE_PACKAGED_AX_E2E=1 RYDDI_ARTIFACT_BASENAME=Ryddi-v0.3.0 Scripts/release-check.sh` exits `0` on the Accessibility-approved release Mac.
- [ ] The signed GitHub release runner has labels `self-hosted`, `macOS`, and `ryddi-release`, is logged into a GUI session, and its runner process has Accessibility approval.
- [ ] `CODESIGN_IDENTITY` is set to a Developer ID Application certificate.
- [ ] `RYDDI_VERSION=0.3.0` and `RYDDI_BUILD_NUMBER=3` are used by the packaging scripts.
- [ ] `Scripts/package-app.sh` signs `dist/Ryddi.app` with Hardened Runtime.
- [ ] `dist/Ryddi.app/Contents/Resources/Ryddi.icns` exists, `CFBundleIconFile=Ryddi`, and the icon is visible in Finder, Dock, About, and the app switcher.
- [ ] `iconutil --convert iconset Assets/Ryddi.icns` recreates all required 16, 32, 128, 256, 512, and 1024 pixel representations.
- [ ] `Scripts/notarize-app.sh dist/Ryddi.app` completes successfully.
- [ ] If notarization is still `In Progress`, the script exits nonzero, prints a `RYDDI_NOTARY_SUBMISSION_ID=...` resume command, and no final `Ryddi-v0.3.0.zip` is published.
- [ ] `dist/Ryddi-notary-status.json` records `"status": "Accepted"` before any manifest claims notarization.
- [ ] Invalid notarization responses save `dist/Ryddi-notary-log.json` for review.
- [ ] Notarization credentials are supplied through `NOTARY_PROFILE` or `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`.
- [ ] `xcrun stapler validate dist/Ryddi.app` passes.
- [ ] `spctl --assess --type execute --verbose dist/Ryddi.app` accepts the app.
- [ ] `codesign --verify --deep --strict --verbose=2 dist/Ryddi.app` passes.
- [ ] `dist/Ryddi-v0.3.0.zip`, `dist/Ryddi-v0.3.0.zip.sha256`, and `dist/Ryddi-release-manifest.txt` exist.
- [ ] `dist/Ryddi-release-manifest.txt` records signed, accepted notarization, stapled, Gatekeeper, strict codesign, bundle version `0.3.0`, build `3`, notary submission ID, and status JSON path proof.
- [ ] The manifest records `packaged_ax_e2e=passed` and `packaged_ax_e2e_proof=included`; the staged release contains `Packaged-App-E2E/`.
- [ ] `reclaimer release-trust --json --manifest dist/Ryddi-release-manifest.txt` reports `state` as `stapledAndAccepted`.
- [ ] The manifest contains parseable release-trust keys: `manifest_schema=ryddi.release-trust.v1`, `codesign_verified=true`, `hardened_runtime=true`, `notarization_status=Accepted`, `stapled=true`, and `gatekeeper=accepted`.
- [ ] GitHub release artifact, checksum, and release manifest are uploaded.

## v0.3.0 Release Notes Template

```markdown
## Ryddi v0.3.0

Trust-to-action polish release.

- Signed and notarized outside the Mac App Store, only if the release manifest proves Developer ID signing, Apple notarization, stapling, Gatekeeper assessment, and strict codesign verification.
- Release artifacts use bundle version `0.3.0`, build `3`, and `Ryddi-v0.3.0` names.
- Trust-to-action app surfaces for Summary, Review Queues, Package Cache, AI Agent Storage, and Remote Targets evidence.
- Report-only remote target evidence, history, dogfood reports, and issue-package exports remain read-only and perform no cleanup.
- Local issue packages and redacted reports improve bug/safety review without uploading private paths.
- Release checklist and signed workflow distinguish unsigned previews from signed/notarized releases.

Non-claims:

- No cleanup is performed by packaging, release-trust checks, dogfood reports, issue packages, or scheduled automation.
- Full Disk Access remains user controlled.
- APFS/free-space gains are estimates, not exact promises.
- Remote Targets do not run remote cleanup, Docker prune/reset, `rm`, sudo cleanup, or unattended destructive SSH maintenance.
- VM/container disks, browser profiles, GarageBand/Logic assets, AI-agent memories, AI-agent sessions, credentials, and unknown app state remain protected by default.
```

## Trust And Safety Notes

- [ ] `PRIVACY.md` is current.
- [ ] `docs/COMPETITIVE_RESEARCH.md` does not overclaim implemented features.
- [ ] CI is green on the release commit.
- [ ] Release notes say automation is report-first.
- [ ] Release notes document the primary app flow as Scan, Plan, Dry Run, exact-path Confirm, Trash, and Recovery.
- [ ] Release notes say only selected auto-safe Trash actions can execute; direct deletion, compression, holding moves, remote cleanup, and scheduled cleanup remain disabled.
- [ ] Release notes document one-time 15-minute authorization, final identity/rule/policy/symlink/gate/open-handle checks, non-atomic pathname caveat, and no immediate free-space gain until Trash is emptied.
- [ ] Release notes say menu bar status is disk-pressure/report-only, not RAM cleaning or performance optimization.
- [ ] Release notes say duplicate review uses local hashes and does not automatically select or delete duplicates.
- [ ] Release notes say Apps & Leftovers related files are review-only; app uninstall previews and dry-run receipts are evidence for manual Finder removal, and `apps uninstall --yes` is rejected.
- [ ] Release notes say AI Agent Storage review is report-only and does not automatically delete sessions, memories, credentials, config, model state, profiles, or unknown agent data.
- [ ] Release notes say native-tool reports are review-first, `native run` defaults to dry-run, `native homebrew cleanup --dry-run --save-audit` captures Homebrew's actual preview output, Homebrew `--yes` runs a fresh same-process preview before the paired cleanup, saved receipts remain evidence only, and Docker/Colima prune/delete/reset plus unallowlisted package-manager cache-clearing commands remain guidance-only.
- [ ] Release notes distinguish logical bytes, allocated estimates, shared hard-link/clone storage, bounded/degraded scan coverage, and observed post-action free-space deltas.
- [ ] Release notes say the only new native perform lanes are exact `docker builder prune --force` and `npm cache clean --force`, each gated by a fresh same-process preview and explicit confirmation; Docker volumes/images/containers/VMs and project dependencies remain guidance-only.
- [ ] `Scripts/storage-truth-smoke.sh` passes using its disposable fixture and does not invoke live Docker, npm, cleanup, or remote commands.
- [ ] Release notes say container inventory runs read-only inspection commands only.
- [ ] Release notes say user protections/exclusions are local path policy, exports can contain private paths/reasons, imports do not delete files or grant permissions, and policy data is not uploaded.
- [ ] Release notes say user rule packs are local, can contain private path fragments/app names/evidence text, are disabled by default unless explicitly included in CLI scans or app scans, cannot grant cleanup actions, and cannot downgrade bundled never-touch protections.
- [ ] Release notes say templates and saved scope sets are scan roots only, saved exports can contain private paths, and selecting either does not grant cleanup permission.
- [ ] Release notes say permission coverage and walkthroughs are local path readability guidance and do not grant or prove global Full Disk Access.
- [ ] Release notes say active-handle reports can include process summaries and do not quit processes or execute cleanup.
- [ ] Release notes say evidence reports are local Markdown files that can include paths and do not execute cleanup.
- [ ] Release notes say disk drill-down is local scan metadata navigation, parent/child rows are not additive reclaim totals, and drill-down does not select cleanup.
- [ ] Release notes say archive reviews are checklists only and do not compress, move, Trash, delete, or select files for cleanup.
- [ ] Release notes say growth reports compare saved local scan snapshots, can include paths, and do not prove exact current disk state or execute cleanup.
- [ ] Release notes say plan reports summarize proposed cleanup locally and do not execute cleanup or replace dry-run receipts.
- [ ] Release notes say receipt reports summarize saved receipts locally and do not rerun cleanup.
- [ ] Release notes say holding records require manual Finder recovery; Trash, native-tool, dry-run, skipped, and failed receipt rows are guidance, not guaranteed undo.
- [ ] Release notes say Trash Review is report-only and does not empty Trash, restore items, move files, or guarantee immediate free-space recovery.
- [ ] Release notes say Browser Cache Review is report-only and does not quit browsers, delete, move, reset, or modify browser caches or protected profile roots.
- [ ] Release notes say Package Cache Review is report-only and does not delete, move, prune, purge, or modify package-manager caches or protected config/auth paths.
- [ ] Release notes say Project Dependencies Review is report-only and does not delete, move, Trash, prune, purge, clean, execute project scripts, or modify project files, source, manifests, lockfiles, env files, dependencies, build outputs, credentials, IDE settings, workspace metadata, generated code, local editable installs, or unknown project state.
- [ ] Release notes say Xcode Review is report-only and does not delete, move, Trash, prune, purge, reset simulators, modify Xcode files, or treat Xcode UserData, signing profiles, accounts, templates, preferences, snippets, archives, DeviceSupport, simulator state, or runtimes as automatically safe.
- [ ] Release notes say Device Backups Review is report-only and does not delete, move, Trash, prune, purge, or modify local device backups.
- [ ] Release notes say report redaction affects exports only; saved local audit JSON, plans, and receipts can still contain original local paths.
- [ ] Release notes say VM/container disks, browser profiles, GarageBand/Logic assets, Codex memories, and Codex sessions are not deleted automatically.
