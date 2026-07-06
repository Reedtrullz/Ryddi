# Ryddi Privacy

Ryddi is local-first disk cleanup software. Its job is to inspect local paths, explain storage usage, and help you build a safe cleanup plan.

## What Stays Local

Ryddi does not upload paths, filenames, app lists, scan results, cleanup plans, receipts, or hardware information.

Scans run on your Mac. Plans, receipts, Markdown evidence/plan/receipt reports, and holding-area metadata are written locally under your user account. The scheduled agent is report-first and writes local audit records; it does not send reports anywhere.

## What Ryddi Reads

Ryddi reads filesystem metadata such as path, file type, size, allocated size, modification date, and readability. When requested by a plan or action, it can run open-file checks so active files are skipped.

Active-handle review runs bounded open-file checks over cleanup-relevant candidates and can save a local report. These reports can include local paths, process names, pids, failed-check messages, safety classes, and guidance. Ryddi does not upload active-handle reports, quit processes, or execute cleanup while creating them.

Disk status and the menu bar item read local volume capacity/free-space metadata. They do not inspect file contents or send disk pressure information anywhere.

Permission coverage checks use local filesystem existence and readability checks for configured scan roots. They can report readable, denied, missing, and unknown scope states, but they do not grant macOS permissions or prove that Full Disk Access is globally enabled.

Duplicate review is different from normal metadata scanning: it reads regular file bytes to compute local SHA-256 content hashes for same-size candidates. File contents are not stored, uploaded, or sent to any remote service. The duplicate CLI requires explicit `--path` roots, and preserve-by-default files are excluded unless the user explicitly opts into that review.

Apps & Leftovers review reads installed app bundle metadata from local `Info.plist` files and checks common user Library locations for related support files, caches, logs, preferences, containers, launch agents, and heuristic orphan candidates. It does not upload app inventory or uninstall apps.

Native-tool reports read scan findings and generate local command preview receipts for tools such as Docker, Colima, Homebrew, and package managers. They can include local paths and command text. Ryddi does not upload these reports and does not execute the native commands automatically.

Container inventory can run read-only Docker and Colima inspection commands. The resulting local reports can include Docker image names, container names, volume names, context endpoints, Colima profile names, command exit states, and short command-output previews. Ryddi does not upload this inventory and does not run prune, delete, stop, reset, or raw VM-disk commands.

User path policy stores local exclusions and protections you create. These entries can include paths and optional reasons. Ryddi uses them locally to skip excluded paths and to keep protected paths blocked from cleanup plans.

Evidence report export reads scan findings, disk status, scan coverage, and user path policy to write local Markdown. Reports can include local paths, configured policy reasons, category names, and non-claims. Ryddi does not upload these reports or execute cleanup while creating them.

Plan report export reads a proposed reclaim plan to write local Markdown. Plan reports can include selected action paths, blocked or review-only paths, safety buckets, condition messages, and reclaim estimates. Ryddi does not upload plan reports or execute cleanup while creating them.

Receipt report export reads saved dry-run or execution receipts to write local Markdown. Receipt reports can include paths, action statuses, action messages, reclaimed-byte estimates, before/after free-space fields, and errors. Ryddi does not upload receipt reports or rerun cleanup while creating them.

Report exports support path privacy controls. `home-relative` reports hide your home-directory prefix, `redacted` reports replace report paths with `<path redacted>`, and user-entered policy reasons can be redacted from exports. These controls affect the generated report only; saved local audit JSON, plans, and receipts can still contain original local paths.

Ryddi works without Full Disk Access, but scan coverage can be incomplete. If macOS denies access to a folder, Ryddi should show degraded coverage rather than pretending the scan was complete.

## What Ryddi Writes

Ryddi can write:

- saved dry-run plans and receipts;
- saved Markdown evidence reports;
- saved Markdown reclaim plan reports;
- saved Markdown receipt reports;
- saved native-tool preview reports;
- saved container inventory reports;
- saved active-file review reports;
- saved user path policy for protections and exclusions;
- compact local scan-history snapshots for growth comparisons;
- app-managed holding-area metadata;
- a per-user LaunchAgent plist if you install report scheduling;
- cleanup changes only after explicit confirmation.

Uncertain user-visible data should go to Trash or the app-managed holding area. Direct delete is reserved for allowlisted reproducible cache/temp data after safety checks.

## What Ryddi Should Never Touch Automatically

Ryddi should never automatically remove credentials, secrets, configs, app state databases, browser profiles, user documents, Photos or Music libraries, GarageBand or Logic assets, Codex memories, Codex sessions, VM/container disks, installed app bundles, app support data, or unknown app-managed state.

## Telemetry

Ryddi has no telemetry in the MVP. If telemetry is ever proposed, it should be opt-in, documented, and unnecessary for local cleanup.

## Removing Local Ryddi Data

Ryddi data is expected under:

```text
~/Library/Application Support/Ryddi
~/Library/Application Support/Ryddi/Config/user-path-policy.json
~/Library/Application Support/Ryddi/ScanHistory
~/Library/Application Support/Ryddi/Reports
~/Library/LaunchAgents/com.reidar.ryddi.agent.plist
```

Remove the LaunchAgent from the app or CLI before deleting app support data.
