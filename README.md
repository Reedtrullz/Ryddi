# Ryddi

[![CI](https://github.com/Reedtrullz/Ryddi/actions/workflows/ci.yml/badge.svg)](https://github.com/Reedtrullz/Ryddi/actions/workflows/ci.yml)

Ryddi is a local-first macOS disk reclaim assistant for general Mac cleanup, with a developer and AI-agent cleanup pack being perfected first.

It is named from Norwegian **ryddig** / **rydde**: tidy, orderly, to clean up. The goal is not to be a scary one-click cleaner. Ryddi scans, explains, plans, and only then helps you reclaim space with receipts and guardrails.

## About

Modern Macs accumulate a strange mix of bloat: Downloads, old installers, caches, logs, large media, app-support leftovers, browser data, developer build products, Codex sessions and caches, Docker and Colima VM data, Xcode artifacts, and package-manager stores. Some of that is pure trash. Some of it is valuable history. Some of it is dangerous to touch directly.

Ryddi treats cleanup as evidence review:

- map where space is going;
- classify each finding by safety;
- explain why it matched;
- check active file handles before action;
- build a dry-run reclaim plan;
- require confirmation before destructive cleanup;
- keep audit receipts locally;
- preserve user data, credentials, sessions, profiles, creative assets, and VM/container state by default.

## Current Status

Ryddi is preparing the `v0.2.0` trust release. It has a shared Swift core, a CLI, and a SwiftUI app cockpit. The safest path today is scan, review, dry run, then reclaim only selected auto-safe items.

`v0.2.0` should be called a signed release only when the release manifest proves Developer ID signing, Apple notarization, stapling, Gatekeeper assessment, and strict codesign verification. Local debug builds and unsigned preview artifacts are useful for testing, but they are not the trust release.

No telemetry, path uploads, remote analysis, root helper, or Mac App Store sandboxing in v1.

See [PRIVACY.md](PRIVACY.md) for the local-only privacy model and what Ryddi should never touch automatically.

## What It Handles

- sortable top-offender overview with category, owner/app/tool, safety, age, logical size, allocated size, confidence, and conservative reclaim estimate
- shared review queues for Safe Maintenance, Quit App First, Use Native Tool, Valuable History, Personal/App Assets, and Unknown findings, with queue-specific CLI filtering and app detail navigation
- scan presets for Developer, General Mac, and All roots, plus scope preview before scanning
- saved custom scope sets for repeatable general cleanup, project review, or developer maintenance scans
- proportional visual map nodes by category, using non-overlapping allocated-size accounting
- hierarchical disk drill-down for scanned roots, with bounded child rows, safety/action/category hints, and explicit non-additive accounting notes
- ownership-aware storage summaries that group findings by app/tool hints such as Codex, Docker, Colima, Xcode, Homebrew, and Chrome
- local scan history snapshots and category growth deltas
- exportable local Markdown growth reports comparing saved scan snapshots
- menu bar disk-pressure status with report-only scan shortcut
- trust readiness cockpit and `reclaimer trust --json` summary for disk pressure, scan coverage, latest plan/receipt state, report-only automation, next-action buckets, and release trust evidence
- dogfood report mode with `reclaimer dogfood --preset general --path-style redacted --output FILE.md`, explicitly proving no cleanup, no permission grant, and no exact APFS reclaim promise
- permission/degraded-scan coverage, first-run Full Disk Access walkthrough, and APFS accounting notes
- exportable local Markdown evidence reports with top findings, safety buckets, user policy, and non-claims
- exportable local Markdown reclaim plan reports with selected actions, blocked items, safety buckets, and non-claims
- exportable local Markdown receipt reports with before/after free-space notes, action counts, skipped/errors, and non-claims
- Recovery Center for app-held restores plus honest Trash, dry-run, skipped, native-tool, and non-recoverable receipt guidance
- report privacy controls for full, home-relative, or redacted paths plus user-entered reason redaction
- transparent rule catalog showing bundled and opt-in local user rules, safety classes, actions, categories, match hints, conditions, recovery notes, and non-claims
- active-handle review for cleanup candidates, with process summaries and failed-check visibility
- Finder, Quick Look, Terminal, and copy-path actions in the app
- local user protections and exclusions for paths Ryddi should preserve or ignore, with JSON import/export
- local user rule-pack preview/import/export in CLI and app for custom review, preserve, and never-touch signals
- first-class large-file and old-file review mode with category/safety summaries, row actions, and no automatic cleanup
- archive-candidate review checklist for large/old personal files, with keep/archive/Trash-review/cleanup-plan/blocked recommendations
- duplicate-file review with local content hashing, explicit CLI paths, and no automatic cleanup
- report-only Downloads review for old downloads, installers, archives, app bundles, Finder workflow buckets, row actions, and local audit history
- report-only Browser Cache review for cache roots, protected profile roots, advisory browser runtime status, quit-first guidance, and local audit history
- report-only Package Cache review for Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, and Playwright cache roots, protected config/auth paths, native-tool guidance, and local audit history
- report-only Project Dependencies review for project-local node_modules, virtual environments, build folders, Pods, framework caches, Flutter/Android outputs, protected project files, optional local VCS status, saved per-project review policies, detected package managers, package names, package.json script-risk previews, workspace-aware native rebuild command hints, and local audit history
- report-only Device Backups review for local iPhone/iPad MobileSync backup size, age, encryption, metadata, Apple/Finder guidance, and local audit history
- report-only Trash review for current user Trash size, largest items, Finder guidance, and local audit history
- report-only Xcode Review for DerivedData, module/documentation caches, Products, Archives, DeviceSupport, simulator devices, runtimes, logs, preview simulators, protected Xcode UserData, and local audit history
- apps-and-leftovers review for installed app support files and heuristic orphan candidates
- app uninstall preview and explicit app-bundle Trash receipts, with related support files kept review-only
- AI-agent storage review for Codex, Claude, Cursor, Windsurf, and Ollama, separating reclaimable cache from valuable history and protected state
- AI-agent retention profiles that recommend old cache cleanup plans, old history compression review, and protected-state keep rules without modifying files
- Codex cache/temp/log/session policy
- Docker and Colima reporting with native-tool guidance
- read-only Docker/Colima inventory for storage buckets, images, containers, volumes, profiles, and command outcomes
- Remote Targets for agentless, report-only SSH/VPS storage evidence: target discovery from SSH config, safe probe, VPS scan, native guidance, redacted Markdown export, saved remote growth diffs, and local audit history
- native-tool command preview and execution receipts for selected non-destructive Homebrew/package-manager cleanup commands, while Docker/Colima destructive commands remain guidance-only
- Xcode DerivedData, module cache, archive, DeviceSupport, simulator, runtime, and developer-state review
- Homebrew, npm, pnpm, Yarn, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, Playwright, JetBrains, VS Code/Cursor/Windsurf, Android, and Flutter cache rules
- Browser cache versus browser profile separation
- Stale temp/scratch review
- App-managed holding area for reversible quarantine moves
- Local audit history for plans, execution receipts, native reports, container reports, active-file reports, and review reports

## Safety Model

Ryddi classifies findings into:

- `autoSafe` - rebuildable cache/temp data that can be selected after checks
- `safeAfterCondition` - likely safe, but requires a condition such as quitting an app or using a native cleanup tool
- `reviewRequired` - useful signal, no automatic action
- `preserveByDefault` - valuable data such as sessions, profiles, assets, archives, or app-managed state
- `neverTouch` - credentials, config, memories, app bundles, active state DBs, and other protected paths

Confirmed reclaim is blocked unless a clean dry-run receipt exists for the current plan. Direct delete is limited to allowlisted reproducible caches. Uncertain user-visible removals use Trash or the app-managed holding area.

## Build

```bash
swift build --scratch-path .build
swift test --scratch-path .build
```

Run the app or CLI from SwiftPM:

```bash
swift run --scratch-path .build RyddiApp
swift run --scratch-path .build reclaimer help
```

## CLI Quick Start

```bash
swift run --scratch-path .build reclaimer overview
swift run --scratch-path .build reclaimer drilldown --preset general --max-depth 3 --limit 8
swift run --scratch-path .build reclaimer scopes --preset general
swift run --scratch-path .build reclaimer scopes templates list
swift run --scratch-path .build reclaimer scopes --template weekly-general
swift run --scratch-path .build reclaimer scopes saved add "Weekly General" --path ~/Downloads --path ~/Library/Caches
swift run --scratch-path .build reclaimer scopes --scope-set "Weekly General"
swift run --scratch-path .build reclaimer overview --scope-set "Weekly General"
swift run --scratch-path .build reclaimer overview --preset general
swift run --scratch-path .build reclaimer overview --preset general --sort reclaim --group safety --limit 25
swift run --scratch-path .build reclaimer queues --preset general --limit 10
swift run --scratch-path .build reclaimer large --preset general --review all --limit 25
swift run --scratch-path .build reclaimer archive --preset general --review all --output ryddi-archive-review.md
swift run --scratch-path .build reclaimer archive --preset general --path-style redacted --output ryddi-archive-review-redacted.md
swift run --scratch-path .build reclaimer scan --preset all --review large
swift run --scratch-path .build reclaimer rules
swift run --scratch-path .build reclaimer rules user preview ryddi-user-rules.json
swift run --scratch-path .build reclaimer rules user import ryddi-user-rules.json
swift run --scratch-path .build reclaimer scan --preset general --include-user-rules
swift run --scratch-path .build reclaimer status
swift run --scratch-path .build reclaimer trust --json
swift run --scratch-path .build reclaimer dogfood --preset general --path-style redacted --output ryddi-dogfood.md
swift run --scratch-path .build reclaimer permissions
swift run --scratch-path .build reclaimer permissions guide --output ryddi-permissions-guide.md
swift run --scratch-path .build reclaimer active --path ~/Library/Caches --limit 25
swift run --scratch-path .build reclaimer overview --save-history --path Tests --limit 5
swift run --scratch-path .build reclaimer report --path Tests --limit 10 --output ryddi-report.md
swift run --scratch-path .build reclaimer report --path Tests --path-style redacted --redact-user-text --output ryddi-report-redacted.md
swift run --scratch-path .build reclaimer history list
swift run --scratch-path .build reclaimer history diff --group category
swift run --scratch-path .build reclaimer history report --output ryddi-growth-report.md
swift run --scratch-path .build reclaimer scan
swift run --scratch-path .build reclaimer scan --sort category --group category --limit 40
swift run --scratch-path .build reclaimer scan --review large --large-threshold 1000000000
swift run --scratch-path .build reclaimer duplicates --path ~/Downloads --min-size 10000000
swift run --scratch-path .build reclaimer trash --save-audit
swift run --scratch-path .build reclaimer apps --min-size 10000000
swift run --scratch-path .build reclaimer apps uninstall-preview --app /Applications/Example.app --output ryddi-app-uninstall-preview.md
swift run --scratch-path .build reclaimer agents
swift run --scratch-path .build reclaimer agents --json --limit 40
swift run --scratch-path .build reclaimer agents retention --profile balanced
swift run --scratch-path .build reclaimer packages --json --save-audit
swift run --scratch-path .build reclaimer projects --json --path ~/Projects --include-vcs-status --save-audit
swift run --scratch-path .build reclaimer projects policy preserve ~/Projects/ImportantApp --reason "keep demo dependencies"
swift run --scratch-path .build reclaimer xcode --json --save-audit
swift run --scratch-path .build reclaimer native --path ~/.colima --save-audit
swift run --scratch-path .build reclaimer native run --command-id brew.preview --path ~/Library/Caches/Homebrew --dry-run --save-audit
swift run --scratch-path .build reclaimer native run --command-id brew.cleanup --path ~/Library/Caches/Homebrew --yes --save-audit
swift run --scratch-path .build reclaimer containers --timeout 5 --save-audit
swift run --scratch-path .build reclaimer remote targets list
swift run --scratch-path .build reclaimer remote probe my-vps --json --timeout 5
swift run --scratch-path .build reclaimer remote scan my-vps --preset vps-general --path-style redacted --output ryddi-vps-report.md
swift run --scratch-path .build reclaimer remote native my-vps
swift run --scratch-path .build reclaimer remote history list
swift run --scratch-path .build reclaimer remote history diff
swift run --scratch-path .build reclaimer remote history report --path-style redacted --output ryddi-vps-growth.md
swift run --scratch-path .build reclaimer policy protect ~/Documents/Important --reason "never clean"
swift run --scratch-path .build reclaimer policy exclude ~/Downloads/NoisyScratch
swift run --scratch-path .build reclaimer policy export --output ryddi-policy.json
swift run --scratch-path .build reclaimer policy import ryddi-policy.json
swift run --scratch-path .build reclaimer plan --json
swift run --scratch-path .build reclaimer plan --path Tests --output ryddi-plan-report.md
swift run --scratch-path .build reclaimer plans export --path-style redacted --output ryddi-plan-report-redacted.md
swift run --scratch-path .build reclaimer explain ~/.codex
swift run --scratch-path .build reclaimer execute --dry-run --path ~/Library/Caches/Codex
swift run --scratch-path .build reclaimer receipts list
swift run --scratch-path .build reclaimer receipts export --output ryddi-receipt-report.md
swift run --scratch-path .build reclaimer receipts export --path-style redacted --output ryddi-receipt-report-redacted.md
swift run --scratch-path .build reclaimer recovery list
swift run --scratch-path .build reclaimer recovery restore HOLDING_ID --to ~/Restored-Ryddi-Item
swift run --scratch-path .build reclaimer holding list
```

Execution is dry-run unless `--yes` is supplied. Even with `--yes`, the executor refuses protected classes, revalidates the path, reclassifies it, and skips open files.

## Install And Release Trust

For local development:

```bash
swift build --scratch-path .build
Scripts/release-check.sh
```

For a signed `v0.2.0` release gate, provide Developer ID and notarization credentials, then run:

```bash
RYDDI_RELEASE_SIGNING=required RYDDI_ARTIFACT_BASENAME=Ryddi-v0.2.0 Scripts/release-check.sh
```

The signed release gate must produce `dist/Ryddi-v0.2.0.zip`, `dist/Ryddi-v0.2.0.zip.sha256`, and `dist/Ryddi-release-manifest.txt` with signed, notarized, stapled, Gatekeeper, and strict codesign proof. If credentials are missing or any check fails, do not publish the build as `v0.2.0`.

## Scope Templates And Saved Scope Sets

Ryddi's presets cover broad modes. Built-in templates cover common review jobs such as weekly general cleanup, personal large-file review, app leftovers, browser caches, package caches, project dependencies, Xcode review, AI-agent storage, and developer maintenance:

```bash
swift run --scratch-path .build reclaimer scopes templates list
swift run --scratch-path .build reclaimer scopes templates show weekly-general
swift run --scratch-path .build reclaimer scopes templates show project-dependencies
swift run --scratch-path .build reclaimer scopes templates show xcode-review
swift run --scratch-path .build reclaimer scan --template weekly-general
swift run --scratch-path .build reclaimer scopes templates save weekly-general --name "Weekly General"
```

Saved scope sets let you reuse specific local roots or customize a saved copy of a template:

```bash
swift run --scratch-path .build reclaimer scopes saved add "Weekly General" --path ~/Downloads --path ~/Library/Caches --summary "General cleanup review"
swift run --scratch-path .build reclaimer scopes saved list
swift run --scratch-path .build reclaimer scopes saved show "Weekly General"
swift run --scratch-path .build reclaimer scan --scope-set "Weekly General"
swift run --scratch-path .build reclaimer scopes saved export --output ryddi-scope-sets.json
swift run --scratch-path .build reclaimer scopes saved import ryddi-scope-sets.json
```

Templates and saved scope sets store scan roots only. They do not grant cleanup permission, change safety rules, or make any path auto-cleanable. Saved scope exports can contain private local paths, so review them before sharing.

## Permission Coverage

## Remote Targets

Remote Targets extends the same evidence-first workflow to SSH/VPS hosts. Ryddi uses your existing SSH config and the system `ssh` client; it does not store keys, passwords, sudo credentials, or install a remote agent.

The first remote release is report-only:

- list non-wildcard SSH aliases from `~/.ssh/config`;
- resolve a target with `ssh -G`;
- probe OS, home directory, disk/inode pressure, available tools, and non-interactive sudo capability;
- scan Linux VPS storage signals such as journald, APT cache, Docker storage, old deploy releases, large files, temp paths, and permission-denied areas;
- export redacted Markdown reports and save local audit records;
- compare saved remote scan audit records locally with `remote history` to see bucket/path growth without reconnecting to the server;
- recommend native commands for manual review.

Ryddi does not run remote cleanup, Docker prune/reset, `rm`, `find -delete`, sudo cleanup, or unattended destructive maintenance in Remote Targets v1.

Remote dogfood evidence packages can be created from a live read-only scan or from saved audit records:

```bash
swift run --scratch-path .build reclaimer remote dogfood my-vps --path-style redacted --output ryddi-vps-dogfood.md --save-audit
swift run --scratch-path .build reclaimer remote dogfood --from-audit my-vps --path-style redacted --output ryddi-vps-dogfood.md
```

`--from-audit` does not reconnect to the server. It compares and packages saved local evidence only.

Remote history reads saved local audit records only:

```bash
swift run --scratch-path .build reclaimer remote history list
swift run --scratch-path .build reclaimer remote history diff --limit 10
swift run --scratch-path .build reclaimer remote history report --path-style redacted --output ryddi-vps-growth.md
```

Remote growth reports compare saved scan-time evidence. They do not prove current server state, exact reclaim, or cleanup safety.

Ryddi can summarize current scan coverage before you review cleanup candidates:

```bash
swift run --scratch-path .build reclaimer permissions
swift run --scratch-path .build reclaimer permissions --json --path ~/Library
swift run --scratch-path .build reclaimer permissions guide --output ryddi-permissions-guide.md
```

The permission advisor reports readable, denied, missing, and unknown scopes; recommends when to review Full Disk Access; and keeps explicit non-claims because path readability is not cleanup permission. The walkthrough adds first-run steps, a settings URL, rescan/report-only commands, affected scopes, and a local Markdown export. It does not grant macOS permissions or prove that Full Disk Access is enabled.

## Disk Drilldown

Ryddi can render a bounded hierarchy for scanned roots:

```bash
swift run --scratch-path .build reclaimer drilldown --preset general --max-depth 3 --limit 8
swift run --scratch-path .build reclaimer drilldown --path ~/Library/Caches --min-size 1000000 --tree-depth 4
```

The drill-down view is for navigation and evidence review. Parent rows include descendant bytes, so parent and child rows should not be added together as independent reclaim totals, and clicking through the app drill-down does not select cleanup.

## Top Offenders

The overview ranks scanned items as a general Mac cleanup queue, not just a developer-cache list:

```bash
swift run --scratch-path .build reclaimer overview --preset general --sort reclaim --group safety --limit 25
swift run --scratch-path .build reclaimer overview --preset all --sort owner --group owner --limit 40
```

Rows include allocated size, logical size, owner/category, safety class, action, cleanup confidence, and estimated immediate reclaim. The reclaim estimate is intentionally conservative: it only counts auto-safe trash/cache-style actions before final open-file, permission, Trash, APFS, and snapshot behavior.

## Review Queues

Ryddi can group scanned findings by the kind of decision they need:

```bash
swift run --scratch-path .build reclaimer queues --preset general --limit 10
swift run --scratch-path .build reclaimer queues --preset all --include-open-files --limit 10
swift run --scratch-path .build reclaimer queues --preset general --queue unknown --limit 25
```

The queues are review surfaces, not cleanup permissions. `Safe Maintenance` can feed dry-run planning only through the normal safety gates, `Quit App First` keeps condition-gated or active data separate, `Use Native Tool` points at tool-owned stores, and protected history/assets remain review-first. The app has a dedicated Review Queues page for moving through one queue at a time and opening each row's evidence detail.

## Large & Old Files

Ryddi can turn large and stale file signals into a dedicated review surface:

```bash
swift run --scratch-path .build reclaimer large --preset general --review all --limit 25
swift run --scratch-path .build reclaimer large --preset general --review old --sort age --old-days 180
swift run --scratch-path .build reclaimer archive --preset general --review all --limit 25
swift run --scratch-path .build reclaimer archive --preset general --path-style redacted --output ryddi-archive-review.md
```

The large/old report prefers concrete child items over broad parent folders when it can do that without obvious double-counting. The archive review turns those rows into a checklist with recommendations such as `Archive`, `Review for Trash`, `Use Cleanup Plan`, `Keep`, `Manual Review`, and `Blocked`.

These rows are not cleanup permission. Archive reviews do not compress, move, Trash, or delete files; use Finder, Quick Look, backups, and the normal dry-run plan before taking action.

## Active Handles

Ryddi can run a focused active-file review for cleanup-relevant candidates:

```bash
swift run --scratch-path .build reclaimer active --path ~/Library/Caches --limit 25
swift run --scratch-path .build reclaimer active --json --save-audit
```

The active review reports paths blocked by open handles or failed open-file checks, including process summaries when `lsof` can provide them. It does not quit apps, execute cleanup, or prove that a path becomes safe after an app exits.

## AI Agent Storage

Ryddi can run a focused review over common AI-agent roots:

```bash
swift run --scratch-path .build reclaimer agents
swift run --scratch-path .build reclaimer agents --json --limit 40
swift run --scratch-path .build reclaimer agents --path ~/.codex --path ~/.claude
swift run --scratch-path .build reclaimer agents retention --profile conservative
swift run --scratch-path .build reclaimer agents retention --profile balanced --json --limit 40
```

The report groups Codex, Claude, Cursor, Windsurf, and Ollama storage into reclaimable cache, quit-first data, valuable history, protected state, and manual review. It is still report-only: agent sessions, memories, credentials, config, model state, and profiles are not deleted automatically, and cache cleanup still goes through the normal plan and dry-run gates.

Retention profiles are also report-only. `conservative`, `balanced`, and `aggressive` change the age thresholds used to recommend old cache cleanup plans, quit-then-cleanup review, compression review for old sessions/history, and protected-state keep rules. They do not delete, compress, move, or modify agent files.

## App Uninstall Preview

Ryddi can build a manual uninstall preview for a selected installed app:

```bash
swift run --scratch-path .build reclaimer apps --min-size 10000000
swift run --scratch-path .build reclaimer apps uninstall-preview --app /Applications/Example.app --output ryddi-app-uninstall-preview.md
swift run --scratch-path .build reclaimer apps uninstall-preview --bundle-id com.example.App --json --save-audit
swift run --scratch-path .build reclaimer apps uninstall --dry-run --app /Applications/Example.app --json --save-audit
swift run --scratch-path .build reclaimer apps uninstall --yes --app /Applications/Example.app --json --save-audit
```

The preview separates the app bundle from related support files. `apps uninstall --dry-run` writes a receipt for moving only the selected app bundle to Trash. `apps uninstall --yes` performs that app-bundle Trash move after open-file, user-policy, and final bundle protection checks. Related caches, preferences, app support, containers, saved state, and launch agents stay review-only/manual. Ryddi does not quit apps, unload helpers, run vendor uninstallers, or clean leftovers automatically.

## Downloads Review

Ryddi can review `~/Downloads` for old downloads, installers, archives, and app bundles without moving anything:

```bash
swift run --scratch-path .build reclaimer downloads --json --save-audit
swift run --scratch-path .build reclaimer downloads --path ~/Downloads --old-days 90 --limit 40
```

Downloads Review reports the configured Downloads root, permission state, total size, installer/archive/old-download candidate bytes, kind summaries, workflow summaries, largest items, and Finder guidance. Rows are bucketed into `Trash Review`, `Archive Review`, `Keep For Now`, or `Manual Review`, with copy/reveal/Quick Look/Terminal actions in the app. It is report-only: Ryddi does not delete, move, archive, compress, or Trash Downloads entries.

## Browser Cache Review

Ryddi can review common browser cache roots while keeping browser profiles out of the cache report:

```bash
swift run --scratch-path .build reclaimer browsers --json --save-audit
swift run --scratch-path .build reclaimer browsers --path ~/Library/Caches/Google/Chrome --home ~ --limit 40
```

Browser Cache Review reports readable/missing cache roots, browser and cache-kind summaries, largest cache items, protected profile roots, advisory browser runtime status from local process-name matching, and quit-first guidance. It is report-only: Ryddi does not delete, move, Trash, reset, quit browsers, or modify browser files, and it does not treat bookmarks, cookies, history, passwords, extensions, sessions, or sync state as cache. Runtime status is a prompt to quit the browser and rerun review or active-handle checks, not proof that all browser work is inactive.

## Package Cache Review

Ryddi can review common package-manager cache roots while keeping config and auth files out of the cache report:

```bash
swift run --scratch-path .build reclaimer packages --json --save-audit
swift run --scratch-path .build reclaimer packages --path ~/Library/Caches/Homebrew --home ~ --limit 40
```

Package Cache Review reports readable/missing cache roots, package-manager and cache-kind summaries, largest cache items, protected config/auth paths, and native cleanup guidance. It is report-only: Ryddi does not delete, move, Trash, prune, purge, or modify package-manager files, and it does not treat tokens, credentials, registries, mirrors, settings, or project behavior as cache.

## Project Dependencies Review

Ryddi can review project-local dependencies and build artifacts without touching source or manifests:

```bash
swift run --scratch-path .build reclaimer projects --json --save-audit
swift run --scratch-path .build reclaimer projects --path ~/Projects --search-depth 6 --max-depth 8 --limit 40 --include-vcs-status
swift run --scratch-path .build reclaimer projects policy list
swift run --scratch-path .build reclaimer projects policy skip-review ~/Projects/NoisyFixture --reason "known generated fixture"
swift run --scratch-path .build reclaimer projects --path ~/Projects --include-policy-skipped
swift run --scratch-path .build reclaimer scopes --template project-dependencies
```

Project Dependencies Review reports readable/missing project roots, ecosystem and artifact-kind summaries, detected project tools, workspace/monorepo evidence, package names, accepted package.json script names, bounded/redacted script command previews, script-risk summaries, largest `node_modules`, `.venv`, `.build`, `target`, `Pods`, `.dart_tool`, framework cache, web build, Gradle, Flutter, and Android build directories, plus protected project roots and native rebuild guidance. Workspace detection recognizes markers such as package.json workspaces, pnpm-workspace.yaml, Lerna/Turbo/Nx/Rush files, Cargo workspaces, and Gradle included subprojects; child packages can inherit the workspace package manager for safer command hints, and hints include the intended working directory plus workspace package selectors where the package manager model supports them. Script command hints are generated only for simple rebuild/cleanup/test script reviews; destructive, lifecycle, deploy, publish, network, and unknown scripts stay manual-review only. With `--include-vcs-status`, it runs local read-only `git status --porcelain=v1 --untracked-files=normal` checks and records whether candidate projects are clean, dirty, untracked-only, not Git repositories, or failed to check. Saved per-project policies can mark known projects as review, preserve, or skip-review; skipped projects are listed as skipped evidence, and `--include-policy-skipped` temporarily inspects them anyway. It is report-only: Ryddi does not delete, move, Trash, prune, purge, clean, execute rebuild commands or project scripts, or modify project files, and it does not treat source, manifests, lockfiles, env files, credentials, IDE settings, workspace metadata, generated code, local editable installs, saved policy choices, or unknown project state as automatically safe.

## Xcode Review

Ryddi can review Xcode developer storage without modifying it:

```bash
swift run --scratch-path .build reclaimer xcode --json --save-audit
swift run --scratch-path .build reclaimer xcode --home ~ --old-days 180 --limit 40
swift run --scratch-path .build reclaimer scopes --template xcode-review
```

Xcode Review reports readable/missing roots, Xcode kind summaries, largest DerivedData/module/documentation/product caches, Archives, DeviceSupport folders, simulator devices, simulator runtimes, logs, preview simulator data, protected developer-state roots, and native Xcode/simctl guidance. It is report-only: Ryddi does not delete, move, Trash, prune, purge, reset simulators, modify Xcode files, or treat Xcode UserData, signing profiles, accounts, templates, preferences, snippets, archives, device-support folders, simulator state, or runtimes as automatically safe.

## Device Backups Review

Ryddi can review local iPhone and iPad MobileSync backups without modifying them:

```bash
swift run --scratch-path .build reclaimer device-backups --json --save-audit
swift run --scratch-path .build reclaimer device-backups --home ~ --old-days 180 --limit 40
```

Device Backups Review reports the configured backup root, permission state, total logical/allocated size, largest backup folders, parsed `Info.plist` device metadata when available, encryption state, old-backup review bytes, and Apple/Finder guidance. It is report-only: Ryddi does not delete, move, Trash, prune, purge, or modify device backups, and it cannot prove whether iCloud Backup or another restorable backup exists.

## Trash Review

Ryddi can review the current user Trash without emptying it:

```bash
swift run --scratch-path .build reclaimer trash --json --save-audit
swift run --scratch-path .build reclaimer trash --path ~/.Trash --limit 40
```

Trash Review reports the configured Trash root, permission state, total logical/allocated size, largest immediate Trash items, and Finder guidance. It is report-only: Ryddi does not empty Trash, restore items, move files, or promise immediate free-space recovery.

## Protections And Exclusions

Ryddi stores local user path policy under Application Support:

```bash
swift run --scratch-path .build reclaimer policy list
swift run --scratch-path .build reclaimer policy protect ~/Projects/KeepMe --reason "active work"
swift run --scratch-path .build reclaimer policy exclude ~/Downloads/NoisyScratch --reason "ignore churn"
swift run --scratch-path .build reclaimer policy remove ~/Downloads/NoisyScratch --kind exclude
swift run --scratch-path .build reclaimer policy export --output ryddi-user-path-policy.json
swift run --scratch-path .build reclaimer policy import ryddi-user-path-policy.json
swift run --scratch-path .build reclaimer policy import ryddi-user-path-policy.json --replace
```

Protected paths stay visible but are forced to preserve-by-default/report-only and cannot be selected by cleanup plans. Excluded paths are skipped during scans and excluded from parent directory measurement. Use `--ignore-user-policy` only for debugging or fixture verification.

Policy import merges by default: matching `kind + path` rules from the import update existing local entries, while unrelated local rules remain. Use `--replace` only when you want the imported file to become the whole policy. Policy exports can contain private local paths and user-entered reasons; importing a policy changes only Ryddi's local protection/exclusion rules and does not delete files, grant macOS permissions, or prove that imported paths still exist.

## User Rule Packs

Ryddi can also import local user rule packs for custom review signals:

```bash
swift run --scratch-path .build reclaimer rules user list
swift run --scratch-path .build reclaimer rules user preview ryddi-user-rules.json
swift run --scratch-path .build reclaimer rules user import ryddi-user-rules.json
swift run --scratch-path .build reclaimer rules user export --output ryddi-user-rules-export.json
swift run --scratch-path .build reclaimer scan --preset general --include-user-rules
swift run --scratch-path .build reclaimer rules --include-user-rules
```

User rules are local, disabled by default for scans, and cannot grant cleanup actions. Imports are limited to `reviewRequired`, `preserveByDefault`, or `neverTouch` signals with report/guidance-style actions. A user rule can make Ryddi more cautious about a path, but it cannot downgrade bundled `neverTouch` rules or turn custom matches into unattended cleanup candidates.

Rule packs can contain private path fragments, app names, or notes. Review before sharing.

In the app, use Rule Catalog -> Local User Rules to preview a JSON pack, inspect validation issues, import the previewed pack, export installed rules, or reveal the local `user-rules.json`. The toolbar `User Rules` toggle is off by default; turning it on opts the next scan into local user rules and clears stale scan/plan state.

## Finding Explanations

Ryddi can explain a single finding as a structured review packet:

```bash
swift run --scratch-path .build reclaimer explain ~/Library/Caches/Codex
swift run --scratch-path .build reclaimer explain ~/Library/Caches/Codex --json
```

The explanation answers what the path appears to be, why it matched, risk, cleanup permission, exact action semantics, removal effect, recovery path, conditions, next steps, and explicit non-claims. It does not execute cleanup or prove that cleanup would succeed.

## Evidence Reports

Ryddi can export a local Markdown report for review, sharing, or before/after notes:

```bash
swift run --scratch-path .build reclaimer report --path ~/Library/Caches --limit 25 --output ryddi-report.md
swift run --scratch-path .build reclaimer report --save-report
```

Reports include scan coverage, safety buckets, top categories, top findings, local protections/exclusions, APFS/accounting notes, disk-pressure notes, and explicit non-claims. They do not execute cleanup and may include local paths.

Use `--path-style home-relative` to hide the home directory prefix, `--path-style redacted` or `--redact-paths` to replace report paths with `<path redacted>`, and `--redact-user-text` to hide user-entered policy reasons. Redaction affects the exported report; saved local audit records may still contain the original paths.

Saved scan history can also be exported as a before/after growth report:

```bash
swift run --scratch-path .build reclaimer overview --save-history --path ~/Library/Caches --limit 25
swift run --scratch-path .build reclaimer history report --group category --output ryddi-growth-report.md
swift run --scratch-path .build reclaimer history report --path-style redacted --output ryddi-growth-report-redacted.md
```

Growth reports compare saved snapshots by category, scope, or safety class. They are evidence for review, not cleanup proof: scope changes, permissions, APFS snapshots, clones, hard links, and purgeable space can make exact free-space deltas differ.

Proposed reclaim plans can also be exported before dry run or execution:

```bash
swift run --scratch-path .build reclaimer plan --path ~/Library/Caches/Codex --output ryddi-plan-report.md
swift run --scratch-path .build reclaimer plan --path ~/Library/Caches/Codex --save-audit
swift run --scratch-path .build reclaimer plans export --path-style redacted --output ryddi-plan-report-redacted.md
```

Plan reports summarize selected actions, blocked or review-only items, safety buckets, conditions, estimates, and non-claims. They do not execute cleanup and are not a substitute for a dry-run receipt.

Saved execution receipts can also be exported:

```bash
swift run --scratch-path .build reclaimer execute --dry-run --path ~/Library/Caches/Codex --save-audit
swift run --scratch-path .build reclaimer receipts export --output ryddi-receipt-report.md
```

Receipt reports summarize saved dry-run or execution receipts. They include action status counts, before/after free-space fields when available, skipped/error actions, and non-claims. Exporting a receipt report does not rerun cleanup.

The Recovery Center combines app-held items and saved receipts:

```bash
swift run --scratch-path .build reclaimer recovery list
swift run --scratch-path .build reclaimer recovery --json
swift run --scratch-path .build reclaimer recovery restore HOLDING_ID
```

Ryddi can restore only items currently in its app-managed holding area. Trash actions require Finder Trash review, dry-run/skipped/error actions should not need recovery, and direct deletes or native-tool cleanup may require rebuilding caches, using the owning tool, or restoring from backup.

Holding-area expiry is also dry-run unless confirmed:

```bash
swift run --scratch-path .build reclaimer holding expire --older-than-days 30
swift run --scratch-path .build reclaimer holding expire --older-than-days 30 --yes
```

## App Bundle

```bash
Scripts/package-app.sh
```

This creates:

```text
dist/Ryddi.app
```

Set `CODESIGN_IDENTITY` to sign locally with Hardened Runtime. Use `Scripts/notarize-app.sh dist/Ryddi.app` when Apple notarization credentials are configured.

For a fuller release-shaped check:

```bash
Scripts/release-check.sh
```

This runs tests, builds `dist/Ryddi.app`, verifies bundled executables and rule resources, smoke-tests the packaged CLI, records signing state, creates `dist/Ryddi-developer-preview.zip`, writes a SHA-256 checksum, and emits `dist/Ryddi-release-manifest.txt`.

Unsigned preview artifacts are intentionally labeled as developer previews. They are not notarization receipts and may trigger Gatekeeper warnings. The manual **Release Preview Artifact** GitHub Actions workflow runs the same check and uploads the zip, checksum, and manifest as CI artifacts.

## Scheduler

```bash
swift run --scratch-path .build reclaimer schedule install
```

The LaunchAgent is report-first. It can target the Developer, General Mac, or All preset, a built-in template, or a saved scope set such as a weekly Downloads/cache review:

```bash
swift run --scratch-path .build reclaimer schedule preview --preset general --kind evidence
swift run --scratch-path .build reclaimer schedule preview --template weekly-general
swift run --scratch-path .build reclaimer schedule preview --scope-set "Weekly General"
swift run --scratch-path .build reclaimer schedule install --scope-set "Weekly General" --hour 9 --minute 30
```

The default installed job runs a dry-run plan:

```bash
reclaimer plan --json --save-audit --preset developer
```

Evidence reports are also supported for broader general-cleaner check-ins:

```bash
reclaimer report --json --save-report --preset general
```

It does not run destructive cleanup unattended, does not call `execute --yes`, and does not run Docker/Colima/Homebrew/package-manager prune commands. A scheduled scope controls where Ryddi looks; it does not make personal files auto-cleanable.

## Native Tool Reports And Receipts

Ryddi treats container runtimes, package-manager stores, and project-local dependency folders as tool-owned state. Use Package Cache Review to inventory global package cache roots, Project Dependencies Review to inspect project-local dependency/build folders, and Device Backups Review to inspect local MobileSync backups before using Apple/Finder-managed backup deletion. For findings such as Docker, Colima, Homebrew, npm, pnpm, Yarn, SwiftPM, Cargo, Go, Gradle, Maven, and CocoaPods, use native-tool reports when you want command-level guidance:

```bash
swift run --scratch-path .build reclaimer native --json --path ~/.colima
```

The report is a preview receipt: command, purpose, risk, expected effect, and non-claims. It can be saved with `--save-audit`, and it is the safest default for Docker, Colima, package stores, and VM/container state.

For selected non-destructive/non-placeholder commands, Ryddi can also create a native command execution receipt:

```bash
swift run --scratch-path .build reclaimer native run --command-id brew.preview --path ~/Library/Caches/Homebrew --dry-run --save-audit
swift run --scratch-path .build reclaimer native run --command-id brew.cleanup --path ~/Library/Caches/Homebrew --yes --save-audit
```

`native run` executes exactly one selected command. It defaults to dry-run, requires `--yes` before performing the command, records stdout/stderr previews and before/after free-space fields, and blocks destructive commands, placeholder commands, shell metacharacters, and raw-delete paths. Ryddi does not run Docker/Colima prune/reset commands automatically and does not raw-delete VM disks, volumes, or package stores.

## Container Inventory

For Docker and Colima, Ryddi can also run read-only inspection commands:

```bash
swift run --scratch-path .build reclaimer containers --json --timeout 5 --save-audit
```

This records Docker storage buckets, images, containers, volumes, contexts, Colima profiles, command exit states, and missing/not-running tool states. It does not run prune, delete, stop, reset, or raw VM-disk commands.

## Repository Layout

```text
Sources/ReclaimerCore/       Shared scanner, rules, planner, executor, audit, recovery, holding, scheduler
Sources/reclaimer/           CLI
Sources/MacDiskReclaimerApp/ SwiftUI app target
Sources/ReclaimerAgent/      Scheduled report runner
Tests/ReclaimerCoreTests/    Safety and fixture tests
Scripts/                     Packaging and notarization helpers
```

## Product Research

- [Competitive research snapshot](docs/COMPETITIVE_RESEARCH.md) - competitor lanes, expected features, and suggested Ryddi roadmap.
- [Release checklist](docs/RELEASE_CHECKLIST.md) - developer preview versus signed/notarized release gates.

## Non-Goals For v1

- automatic duplicate cleanup, smart duplicate selection, or Photos/Music duplicate management
- automatic app-support cleanup, bulk app uninstall, vendor uninstaller execution, or smart leftover deletion
- malware scanning
- RAM cleaning or "optimizer" features
- root helper/system-wide cleanup
- automatic deletion of review-required items
- raw deletion of Docker/Colima VM disks or volumes
- automatic execution of Docker/Colima/Homebrew/package-manager prune/reset commands
- Mac App Store sandbox distribution

## GitHub About

Short description:

```text
Local-first macOS disk reclaim assistant for general cleanup with developer-first rules.
```

Topics:

```text
macos swift swiftui disk-cleanup mac-cleaner developer-tools codex docker colima xcode local-first privacy
```

## License

MIT.
