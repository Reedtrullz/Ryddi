# Ryddi Remote Targets

Remote Targets extends Ryddi's evidence-first cleanup workflow to SSH/VPS hosts without turning Ryddi into a remote admin tool.

## What It Does

- Reads existing SSH aliases from `~/.ssh/config`.
- Resolves one target with `ssh -G`.
- Runs bounded read-only SSH probes with `BatchMode=yes`, `NumberOfPasswordPrompts=0`, `StrictHostKeyChecking=yes`, and a short connect timeout.
- Reports Linux VPS disk and inode pressure, journald size, APT cache size, Docker storage estimates, old deploy release directories, large files, remote temp paths, app data, and permission-denied areas.
- Emits manual native guidance for journald, APT, Docker, and deploy release review.
- Saves local JSON audit records and optional Markdown reports.

## CLI

```bash
swift run --scratch-path .build reclaimer remote targets list
swift run --scratch-path .build reclaimer remote probe my-vps --json --timeout 5
swift run --scratch-path .build reclaimer remote scan my-vps --preset vps-general --path-style redacted --output ryddi-vps-report.md
swift run --scratch-path .build reclaimer remote native my-vps
swift run --scratch-path .build reclaimer remote plan my-vps --json
```

## Safety Contract

Remote Targets v1 is report-only. It does not run remote cleanup, Docker prune, Docker reset, `rm`, `find -delete`, sudo cleanup, package cleanup, database cleanup, or unattended destructive maintenance.

Ryddi does not store SSH private keys, passwords, passphrases, sudo passwords, tokens, or remote secrets. It uses the system SSH client and the user's existing SSH setup.

`sudo -n true` is a capability probe only. If it fails, Ryddi records that non-interactive sudo is unavailable and continues with report-only evidence where possible.

## Preserve By Default

Remote reports preserve or require manual review for:

- Docker volumes;
- databases and dumps;
- backups;
- app uploads and app state;
- `/etc` and other configuration paths;
- credentials and secrets;
- unknown server data;
- anything requiring sudo cleanup.

## Redaction Limits

`--path-style redacted` hides full remote paths in Markdown reports. Reports can still reveal host aliases, usernames, hostnames, filesystem names, service names, Docker object names, command labels, sizes, counts, and error text. Review reports before sharing them.

## Deferred

- Remote cleanup execution.
- Remote Docker prune/reset execution.
- Sudo password management.
- Remote agent installation.
- Secrets inventory.
- Database cleanup.
- macOS or Windows remote cleanup.
