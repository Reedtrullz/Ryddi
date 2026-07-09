# Ryddi Remote Targets

Remote Targets extends Ryddi's evidence-first cleanup workflow to SSH/VPS hosts without turning Ryddi into a remote admin tool.

## What It Does

- Reads existing SSH aliases from `~/.ssh/config`.
- Resolves one target with `ssh -G`.
- Runs bounded read-only SSH probes with `BatchMode=yes`, `NumberOfPasswordPrompts=0`, `StrictHostKeyChecking=yes`, and a short connect timeout.
- Reports Linux VPS disk and inode pressure, journald size, APT cache size, Docker storage estimates, old deploy release directories, large files, remote temp paths, app data, and permission-denied areas.
- Labels each scan as `complete`, `partial`, `unreachable`, or `unsupported` from command outcomes so missing evidence is not treated as a clean host.
- Emits manual native guidance and copyable command cards for journald, APT, Docker, and deploy release review. Ryddi never runs these cards remotely.
- Shows coverage rows for connection, host key, Linux detection, disk filesystems, inodes, Docker, journald, and APT cache so partial scans have concrete reasons.
- Compares saved reachable remote scan audit records locally so you can see bucket and path growth without reconnecting to the host.
- Shows saved bucket changes in `remote scan` text output when a comparable previous scan exists.
- Packages remote dogfood Markdown from a live read-only scan or disposable saved local audit records.
- Exports a redacted local issue package for debugging Ryddi results without copying raw SSH config, private keys, or arbitrary audit JSON.
- Saves local JSON audit records and optional Markdown reports.

## CLI

```bash
swift run --scratch-path .build reclaimer remote targets list
swift run --scratch-path .build reclaimer remote probe my-vps --json --timeout 5
swift run --scratch-path .build reclaimer remote scan my-vps --preset vps-general --path-style redacted --output ryddi-vps-report.md
swift run --scratch-path .build reclaimer remote dogfood my-vps --path-style redacted --output ryddi-vps-dogfood.md --save-audit
swift run --scratch-path .build reclaimer remote dogfood --from-audit my-vps --path-style redacted --output ryddi-vps-dogfood.md
swift run --scratch-path .build reclaimer remote native my-vps
swift run --scratch-path .build reclaimer remote plan my-vps --json
swift run --scratch-path .build reclaimer remote history list
swift run --scratch-path .build reclaimer remote history diff --limit 10
swift run --scratch-path .build reclaimer remote history report --path-style redacted --output ryddi-vps-growth.md
swift run --scratch-path .build reclaimer issue package --path-style redacted --include-remote --output ryddi-issue-package
```

## Safety Contract

Remote Targets v1 is report-only. It does not run remote cleanup, Docker prune, Docker reset, `rm`, `find -delete`, sudo cleanup, package cleanup, database cleanup, or unattended destructive maintenance.

Ryddi does not store SSH private keys, passwords, passphrases, sudo passwords, tokens, or remote secrets. It uses the system SSH client and the user's existing SSH setup.

`sudo -n true` is a capability probe only. If it fails, Ryddi records that non-interactive sudo is unavailable and continues with report-only evidence where possible.

Remote history reads saved local audit records only. It does not open SSH, run probe commands, refresh facts, or prove current server state. Growth deltas are review signals from scan-time evidence.

Unreachable scans can be exported as explicit degraded Markdown evidence, but they are not saved as normal audit records by default and are excluded from default remote growth comparisons.

`reclaimer remote dogfood --from-audit` also reads saved local audit records only. It does not reconnect to the host, does not retry SSH, and does not mutate the server while packaging Markdown evidence.

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

`--path-style redacted` hides full remote paths in Markdown reports and applies best-effort redaction to target aliases, resolved host/user fields, path fragments, Docker-like object names, deploy-release fragments, command-card text, and SSH private-key markers in command previews. Review reports before sharing them; redaction is defensive, not a secrets scanner.

Remote growth reports can still reveal bucket names, size deltas, and whether storage grew or shrank. Saved local audit JSON may still contain original remote paths and host metadata.

## Deferred

- Remote cleanup execution.
- Remote Docker prune/reset execution.
- Sudo password management.
- Remote agent installation.
- Secrets inventory.
- Database cleanup.
- macOS or Windows remote cleanup.
