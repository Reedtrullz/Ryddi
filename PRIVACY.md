# Ryddi Privacy

Ryddi is local-first disk cleanup software. Its job is to inspect local paths, explain storage usage, and help you build a safe cleanup plan.

## What Stays Local

Ryddi does not upload paths, filenames, app lists, scan results, cleanup plans, receipts, or hardware information.

Scans run on your Mac. Plans, receipts, Markdown evidence/plan/receipt reports, and holding-area metadata are written locally under your user account. The scheduled agent is report-first and writes local audit records; it does not send reports anywhere.

## What Ryddi Reads

Ryddi reads filesystem metadata such as path, file type, size, allocated size, modification date, and readability. When requested by a plan or action, it can run open-file checks so active files are skipped.

Scan presets control which local roots are inspected. Developer mode focuses on developer and AI-agent storage, General Mac mode includes broader review roots such as Downloads, Desktop, personal media/document folders, user caches/logs, app support, attachments, backups, and Trash, and All combines both while collapsing overlapping roots. Built-in templates and saved scope sets store scan roots for repeatable scans. Presets, templates, and saved scope sets do not upload data, grant cleanup permission, or change safety rules.

Disk drill-down reports reuse local scan metadata to build a bounded hierarchy of paths, sizes, safety classes, actions, categories, owner hints, and short evidence strings. Ryddi does not upload drill-down reports, and drill-down navigation does not select or execute cleanup.

Active-handle review runs bounded open-file checks over cleanup-relevant candidates and can save a local report. These reports can include local paths, process names, pids, failed-check messages, safety classes, and guidance. Ryddi does not upload active-handle reports, quit processes, or execute cleanup while creating them.

Disk status and the menu bar item read local volume capacity/free-space metadata. They do not inspect file contents or send disk pressure information anywhere.

Permission coverage checks use local filesystem existence and readability checks for configured scan roots. They can report readable, denied, missing, and unknown scope states, but they do not grant macOS permissions or prove that Full Disk Access is globally enabled. Permission walkthrough exports are local Markdown/JSON guidance derived from the same local readback; opening settings or saving a guide does not change macOS privacy state.

Duplicate review is different from normal metadata scanning: it reads regular file bytes to compute local SHA-256 content hashes for same-size candidates. File contents are not stored, uploaded, or sent to any remote service. The duplicate CLI requires explicit `--path` roots, and preserve-by-default files are excluded unless the user explicitly opts into that review.

Apps & Leftovers review reads installed app bundle metadata from local `Info.plist` files and checks common user Library locations for related support files, caches, logs, preferences, containers, launch agents, and heuristic orphan candidates. It does not upload app inventory or uninstall apps.

App uninstall previews reuse the same local app inventory and related-file evidence to create a local checklist for one selected app. The preview can identify the selected app bundle as a manual Trash candidate, but related support files remain review-only/manual. Creating a preview does not quit apps, unload helpers, call vendor uninstallers, delete files, clean leftovers, or upload app inventory.

Device Backups Review reads local filesystem metadata from the configured MobileSync backup root and, when present, each backup folder's local `Info.plist`. Reports can include local backup paths, device names, product names/types, last-backup dates, encryption state, metadata state, size, age, and guidance. Ryddi does not upload this report and does not delete, move, Trash, prune, purge, or modify device backups.

Xcode Review reads local filesystem metadata from configured Xcode and CoreSimulator roots and, when present, local archive `Info.plist` files and simulator `device.plist` files. Reports can include local paths, app/archive names, simulator names, runtime names, DeviceSupport versions, protected Xcode developer-state paths, sizes, ages, and guidance. Ryddi does not upload this report and does not delete, move, Trash, prune, purge, reset simulators, modify Xcode files, or treat Xcode UserData, signing profiles, accounts, templates, preferences, snippets, archives, DeviceSupport, simulator state, or runtimes as automatically safe.

Project Dependencies Review reads local filesystem metadata from configured project roots and recognizes common project-local dependency/build directories such as `node_modules`, `.venv`, `.build`, `target`, `Pods`, `.dart_tool`, framework caches, Gradle caches, Flutter build output, and Android build output. Reports can include local project paths, project names, manifest hints, ecosystem labels, artifact kinds, sizes, ages, optional local Git status summaries from `git status --porcelain=v1 --untracked-files=normal`, saved per-project policy decisions/reasons, command hints, and guidance. Ryddi does not upload this report and does not delete, move, Trash, prune, purge, clean, execute rebuild commands, or modify project files, dependencies, build outputs, source, manifests, lockfiles, env files, credentials, IDE settings, generated code, local editable installs, saved policy choices, or unknown project state.

AI-agent storage review reads local filesystem metadata from common Codex, Claude, Cursor, Windsurf, and Ollama roots, or from explicit paths you provide. Results can include local paths, owner hints, rule IDs, bucket names, and evidence strings. Ryddi does not upload this report, inspect prompt contents for remote analysis, or automatically delete sessions, memories, credentials, config, model state, profiles, or unknown agent data.

Native-tool reports read scan findings and generate local command preview receipts for tools such as Docker, Colima, Homebrew, and package managers. They can include local paths and command text. Ryddi does not upload these reports and does not execute the native commands automatically.

Container inventory can run read-only Docker and Colima inspection commands. The resulting local reports can include Docker image names, container names, volume names, context endpoints, Colima profile names, command exit states, and short command-output previews. Ryddi does not upload this inventory and does not run prune, delete, stop, reset, or raw VM-disk commands.

User path policy stores local exclusions and protections you create. These entries can include paths and optional reasons. Ryddi uses them locally to skip excluded paths and to keep protected paths blocked from cleanup plans.

Project dependency policies store local project review choices you create. These entries can include project root paths, project names, review/preserve/skip decisions, and optional reasons. Ryddi uses them locally to annotate Project Dependencies reports or skip known-noisy projects from that report by default; policies do not grant cleanup permission.

Policy export writes a local JSON document containing those paths, reasons, timestamps, schema version, and non-claims. Ryddi does not upload the export. Review it before sharing because it can reveal project names, usernames, customer names, or other private path details. Policy import changes only Ryddi's local path policy; it does not delete files, run cleanup, grant Full Disk Access, or prove that imported paths still exist. Import merges by default and replaces the whole policy only when `--replace` is supplied.

User rule packs store local classification rules you import. These entries can include match patterns, app names, path fragments, rule titles, categories, evidence text, recovery text, and conditions. Ryddi does not upload rule packs. Imported user rules are disabled by default for scans unless `--include-user-rules` is supplied in the CLI or the app User Rules scan toggle is on, and validation rejects rules that try to grant cleanup actions or unattended cleanup safety. User rules can make a path more cautious to review, preserve, or never-touch; they cannot downgrade bundled never-touch protections.

Saved scope sets store local scan root names and paths for reuse. Ryddi does not upload scope sets. Scope-set export writes local JSON and can reveal usernames, project names, app names, client folders, or personal folder structure, so review exports before sharing. Importing a scope set changes only what roots Ryddi scans when selected; it does not grant cleanup permission or change safety classification.

Evidence report export reads scan findings, disk status, scan coverage, and user path policy to write local Markdown. Reports can include local paths, configured policy reasons, category names, and non-claims. Ryddi does not upload these reports or execute cleanup while creating them.

Plan report export reads a proposed reclaim plan to write local Markdown. Plan reports can include selected action paths, blocked or review-only paths, safety buckets, condition messages, and reclaim estimates. Ryddi does not upload plan reports or execute cleanup while creating them.

Receipt report export reads saved dry-run or execution receipts to write local Markdown. Receipt reports can include paths, action statuses, action messages, reclaimed-byte estimates, before/after free-space fields, and errors. Ryddi does not upload receipt reports or rerun cleanup while creating them.

Recovery Center reads local holding-area metadata and saved execution receipts to show what Ryddi can restore directly and what needs Trash, native-tool, backup, or manual review. Recovery output can include original paths, held paths, receipt IDs, action statuses, and guidance. Ryddi can restore only app-held items; it does not upload recovery data or silently recover/delete receipt-only items.

Growth report export reads saved scan-history snapshots to write local Markdown. Growth reports can include category, scope, safety, scan coverage, and current top finding paths. Ryddi does not upload growth reports or execute cleanup while creating them.

Report exports support path privacy controls. `home-relative` reports hide your home-directory prefix, `redacted` reports replace report paths with `<path redacted>`, and user-entered policy reasons can be redacted from exports. These controls affect the generated report only; saved local audit JSON, plans, receipts, and scan snapshots can still contain original local paths.

Ryddi works without Full Disk Access, but scan coverage can be incomplete. If macOS denies access to a folder, Ryddi should show degraded coverage rather than pretending the scan was complete.

## What Ryddi Writes

Ryddi can write:

- saved dry-run plans and receipts;
- saved Markdown evidence reports;
- saved Markdown reclaim plan reports;
- saved Markdown receipt reports;
- saved Markdown growth reports;
- saved native-tool preview reports;
- saved container inventory reports;
- saved active-file review reports;
- saved report-only review reports for Downloads, browser caches, package caches, project dependencies, Xcode storage, device backups, and Trash;
- saved user path policy for protections and exclusions;
- saved project dependency policy for per-project review choices;
- saved user rule packs for custom review/protection signals;
- saved scope sets for repeatable scan roots;
- compact local scan-history snapshots for growth comparisons;
- app-managed holding-area metadata;
- a per-user LaunchAgent plist if you install report scheduling;
- cleanup changes only after explicit confirmation.

Uncertain user-visible data should go to Trash or the app-managed holding area. Direct delete is reserved for allowlisted reproducible cache/temp data after safety checks.

## What Ryddi Should Never Touch Automatically

Ryddi should never automatically remove credentials, secrets, configs, app state databases, browser profiles, user documents, Photos or Music libraries, GarageBand or Logic assets, AI-agent memories, AI-agent sessions, model state, VM/container disks, installed app bundles, app support data, or unknown app-managed state.

## Telemetry

Ryddi has no telemetry in the MVP. If telemetry is ever proposed, it should be opt-in, documented, and unnecessary for local cleanup.

## Removing Local Ryddi Data

Ryddi data is expected under:

```text
~/Library/Application Support/Ryddi
~/Library/Application Support/Ryddi/Config/user-path-policy.json
~/Library/Application Support/Ryddi/Config/project-dependency-policy.json
~/Library/Application Support/Ryddi/Config/user-rules.json
~/Library/Application Support/Ryddi/ScanHistory
~/Library/Application Support/Ryddi/Reports
~/Library/Application Support/Ryddi/Reports/user-path-policy-*.json
~/Library/Application Support/Ryddi/Reports/project-dependency-policy-*.json
~/Library/LaunchAgents/com.reidar.ryddi.agent.plist
```

Remove the LaunchAgent from the app or CLI before deleting app support data.
