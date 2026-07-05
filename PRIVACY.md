# Ryddi Privacy

Ryddi is local-first disk cleanup software. Its job is to inspect local paths, explain storage usage, and help you build a safe cleanup plan.

## What Stays Local

Ryddi does not upload paths, filenames, app lists, scan results, cleanup plans, receipts, or hardware information.

Scans run on your Mac. Plans, receipts, and holding-area metadata are written locally under your user account. The scheduled agent is report-first and writes local audit records; it does not send reports anywhere.

## What Ryddi Reads

Ryddi reads filesystem metadata such as path, file type, size, allocated size, modification date, and readability. When requested by a plan or action, it can run open-file checks so active files are skipped.

Disk status and the menu bar item read local volume capacity/free-space metadata. They do not inspect file contents or send disk pressure information anywhere.

Duplicate review is different from normal metadata scanning: it reads regular file bytes to compute local SHA-256 content hashes for same-size candidates. File contents are not stored, uploaded, or sent to any remote service. The duplicate CLI requires explicit `--path` roots, and preserve-by-default files are excluded unless the user explicitly opts into that review.

Apps & Leftovers review reads installed app bundle metadata from local `Info.plist` files and checks common user Library locations for related support files, caches, logs, preferences, containers, launch agents, and heuristic orphan candidates. It does not upload app inventory or uninstall apps.

Ryddi works without Full Disk Access, but scan coverage can be incomplete. If macOS denies access to a folder, Ryddi should show degraded coverage rather than pretending the scan was complete.

## What Ryddi Writes

Ryddi can write:

- saved dry-run plans and receipts;
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
~/Library/Application Support/Ryddi/ScanHistory
~/Library/LaunchAgents/com.reidar.ryddi.agent.plist
```

Remove the LaunchAgent from the app or CLI before deleting app support data.
