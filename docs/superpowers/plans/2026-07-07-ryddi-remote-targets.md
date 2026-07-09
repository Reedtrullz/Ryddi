# Ryddi Remote Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Ryddi Remote Targets so Ryddi can connect to SSH/VPS targets, gather disk-cleanup evidence, classify remote storage risk, and produce safe reports/native guidance without running destructive remote cleanup.

**Architecture:** Add an agentless SSH lane to `ReclaimerCore` using the system `/usr/bin/ssh`, existing SSH config, bounded command output, and fakeable command runners. Remote Targets reuse Ryddi's report-first trust model, audit store, privacy redaction, review queues, and SwiftUI cockpit patterns. No remote agent, key storage, telemetry, sudo password flow, or remote delete/execute path in the first release.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, macOS 14+, OpenSSH client, existing `ToolCommandRunning`, local JSON audit records, Markdown report export.

## Global Constraints

- Before long build/test loops, run `df -h /System/Volumes/Data`; stop if free space is below `50Gi`.
- Use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"`.
- Preserve Ryddi's v0.2 trust posture: no telemetry, path upload, remote AI analysis, root helper, or Mac App Store sandboxing.
- Remote v1 is read-only/report-first: no `remote execute`, no raw deletes, no prune/reset run, no unattended destructive action.
- Use `/usr/bin/ssh` with `BatchMode=yes`, `NumberOfPasswordPrompts=0`, `StrictHostKeyChecking=yes`, bounded timeout/output, and no agent forwarding requested by Ryddi.
- Do not store private keys, passwords, sudo passwords, tokens, or remote secrets.
- Treat Docker volumes, databases, backups, `/etc`, credentials, app data, unknown state, and remote user data as preserve/review by default.
- Remote command output is untrusted; parse only bounded allowlisted command shapes.

---

## Key Interfaces

Create focused remote files under `Sources/ReclaimerCore/`:

```swift
public enum RemoteScanPreset: String, Codable, CaseIterable, Sendable {
    case vpsGeneral = "vps-general"
}

public struct RemoteTargetReference: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let input: String
    public let alias: String?
    public let resolvedUser: String?
    public let resolvedHost: String?
    public let resolvedPort: Int?
    public let knownHostsState: String
    public let fingerprint: String?
}

public struct RemoteCommandResult: Codable, Hashable, Sendable {
    public let commandID: String
    public let displayCommand: String
    public let exitCode: Int32?
    public let timedOut: Bool
    public let stdoutPreview: [String]
    public let stderrPreview: [String]
    public let redactionApplied: Bool
}

public struct RemoteProbeReport: Codable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let target: RemoteTargetReference
    public let osSummary: String?
    public let homeDirectory: String?
    public let sudoNonInteractive: Bool?
    public let availableTools: [String]
    public let commands: [RemoteCommandResult]
    public let nonClaims: [String]
}

public struct RemoteStorageFinding: Codable, Identifiable, Sendable {
    public let id: String
    public let remotePath: String
    public let displayPath: String
    public let bucket: String
    public let allocatedBytes: Int64?
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let evidence: [Evidence]
    public let recommendedNextAction: ReviewNextAction
}

public struct RemoteScanReport: Codable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let preset: RemoteScanPreset
    public let target: RemoteTargetReference
    public let diskFilesystems: [RemoteFilesystemSummary]
    public let inodeFilesystems: [RemoteFilesystemSummary]
    public let findings: [RemoteStorageFinding]
    public let nativeGuidance: [RemoteNativeGuidance]
    public let commands: [RemoteCommandResult]
    public let nonClaims: [String]
}
```

Add:

- `RemoteTargetResolver`: parses non-wildcard `Host` aliases from `~/.ssh/config` and uses `ssh -G TARGET` for resolution.
- `RemoteSSHCommandRunner`: wraps `/usr/bin/ssh` safely; fakeable in tests.
- `RemoteProbeBuilder`: runs read-only probe commands and summarizes OS/tools/sudo capability.
- `RemoteScanBuilder`: runs read-only `df`, `du`, `find`, `journalctl --disk-usage`, apt cache, and Docker inventory commands.
- `RemoteNativeGuidanceBuilder`: emits manual/native guidance only; no execution path.
- `RemoteReportBuilder`: Markdown export with `full`, `home-relative`, and `redacted` path styles.
- `AuditStore` additions: save/list recent `RemoteProbeReport` and `RemoteScanReport`.

Add CLI:

```text
reclaimer remote targets list [--json]
reclaimer remote probe TARGET [--json] [--timeout SECONDS] [--save-audit]
reclaimer remote scan TARGET [--preset vps-general] [--json] [--timeout SECONDS] [--path-style full|home-relative|redacted] [--output FILE] [--save-audit]
reclaimer remote native TARGET [--json] [--timeout SECONDS]
reclaimer remote plan TARGET [--json] [--timeout SECONDS]
```

Do not add:

```text
reclaimer remote execute
reclaimer remote prune
reclaimer remote reset
```

## Tasks

### Task 1: Persist The Plan And Baseline

- [ ] Write this plan to `docs/superpowers/plans/2026-07-07-ryddi-remote-targets.md`.
- [ ] Run `df -h /System/Volumes/Data`; stop if free space is below `50Gi`.
- [ ] Run `swift test --scratch-path "$PWD/.build"` to establish baseline.
- [ ] Commit only the plan file with `docs: add remote targets implementation plan`.

### Task 2: Remote Models And Target Resolution

- [ ] Write tests for `RemoteTargetReference`, non-wildcard SSH alias parsing, wildcard skip, and `ssh -G` resolution parsing.
- [ ] Implement `RemoteScanPreset`, `RemoteTargetReference`, `RemoteFilesystemSummary`, `RemoteStorageFinding`, `RemoteProbeReport`, and `RemoteScanReport`.
- [ ] Implement `RemoteTargetResolver` using `~/.ssh/config`, one-level `Include` support, and `ssh -G TARGET` output parsing.
- [ ] Add audit save/read helpers for remote probe and scan reports.
- [ ] Verify with `swift test --scratch-path "$PWD/.build" --filter RemoteTarget`.

### Task 3: Safe SSH Transport

- [ ] Write tests proving every SSH invocation includes `BatchMode=yes`, `NumberOfPasswordPrompts=0`, `StrictHostKeyChecking=yes`, `ConnectTimeout`, bounded timeout, and no `ForwardAgent`.
- [ ] Write tests proving `StrictHostKeyChecking=no`, password prompts, sudo password prompts, `prune`, `reset`, `delete`, and remote execute verbs are never generated by the runner.
- [ ] Implement `RemoteSSHCommandRunner` over `ToolCommandRunning`, with max output `512_000` bytes and max timeout `60` seconds.
- [ ] Implement command IDs and display commands without exposing identity file paths by default.
- [ ] Verify with `swift test --scratch-path "$PWD/.build" --filter RemoteSSH`.

### Task 4: Probe And Parser Pack

- [ ] Write parser tests for Linux `/etc/os-release`, `df -Pk`, `df -Pi`, `du -k`, `journalctl --disk-usage`, apt cache `du`, and Docker text inventory.
- [ ] Implement probe commands: `uname -srm`, `hostname`, `id -un`, `printf "$HOME"`, bounded `/etc/os-release`, `df -Pk`, `df -Pi`, `command -v docker journalctl apt-get sudo`, and `sudo -n true`.
- [ ] Interpret sudo as capability only; never prompt and never run cleanup.
- [ ] Mark unsupported/non-Linux hosts as reportable but degraded.
- [ ] Verify with `swift test --scratch-path "$PWD/.build" --filter RemoteProbe`.

### Task 5: Remote Scan, Queues, And Native Guidance

- [ ] Write tests for VPS buckets: disk pressure, inode pressure, journald logs, apt cache, Docker images/containers/build cache, Docker volumes, old deploy releases, large files, temp dirs, permission denied, and unknown.
- [ ] Implement read-only scan commands for `df`, `du` over `/var /home /opt /srv /tmp /var/tmp /var/log /var/lib`, large-file `find`, journald disk usage, apt cache size, Docker `system df -v`, Docker `ps/images/volume ls`.
- [ ] Classify remote findings with no auto-selection: use `reviewRequired`, `safeAfterCondition`, `preserveByDefault`, or `neverTouch`; never emit remote `autoSafe` cleanup.
- [ ] Emit native guidance for manual `journalctl --vacuum-*`, `apt-get clean/autoclean/autoremove --dry-run`, Docker inspect/prune review, and deploy-release review.
- [ ] Build Markdown reports with explicit non-claims: no cleanup executed, no permission granted, no exact reclaim promise, no root/sudo management.
- [ ] Verify with `swift test --scratch-path "$PWD/.build" --filter RemoteScan`.

### Task 6: CLI Remote Command

- [ ] Add `remote` dispatch and help text.
- [ ] Implement `remote targets list`, `remote probe`, `remote scan`, `remote native`, and `remote plan`.
- [ ] Support `--json`, `--timeout`, `--save-audit`, `--output`, and `--path-style`.
- [ ] Reject `remote execute`, `remote prune`, and `remote reset` with a clear safety error.
- [ ] Add smoke tests through `ReclaimerCLI.run(arguments:)` where possible.
- [ ] Verify `swift run --scratch-path .build reclaimer remote targets list --json`.
- [ ] Verify `swift run --scratch-path .build reclaimer remote probe example --json` fails safely if no host exists and does not prompt.

### Task 7: SwiftUI Remote Targets Cockpit

- [ ] Add sidebar entry `Remote Targets`.
- [ ] Add a target selector/input, Probe button, Scan button, Export Redacted button, and Save Audit affordance.
- [ ] Show cards for Connection, Host Key, OS, Disk Pressure, Scan Coverage, Native Guidance, Review Queues, Command Receipts, and Non-Claims.
- [ ] Disable all reclaim/destructive UI for remote reports.
- [ ] Use existing row/action patterns and next-action chips.
- [ ] Verify with `swift build --scratch-path "$PWD/.build"` and a manual app smoke.

### Task 8: Docs, Privacy, And Evidence Language

- [ ] Document Remote Targets as agentless SSH, report-first, and no-cleanup in v1.
- [ ] Add privacy section for SSH aliases, resolved host/user/port, known_hosts fingerprints, remote paths, command previews, Docker object names, and redaction limits.
- [ ] Add CLI examples using redacted reports.
- [ ] Add explicit deferred scope: no remote execute, no sudo password management, no agent install, no secrets inventory, no database cleanup.
- [ ] Verify docs with `rg -n "remote execute|StrictHostKeyChecking=no|password"` and ensure unsafe patterns appear only as blocked/non-goals.

### Task 9: Final Verification And Parallel Synthesis

- [ ] Run `swift test --scratch-path "$PWD/.build"`.
- [ ] Run `swift build --scratch-path "$PWD/.build"`.
- [ ] Run `Scripts/release-check.sh` only if disk headroom is still above `50Gi`.
- [ ] Run `git diff --check`.
- [ ] Optionally test one real SSH target only with user-approved alias and read-only commands.
- [ ] Log final evidence to Obsidian Daily `## Log` and `Personal/Projects/Mac Disk Reclaimer.md` when outside Plan Mode.
- [ ] Commit in small slices: models, transport, probe/parsers, scan/guidance, CLI/audit, UI, docs/tests.

## Parallel Worker Goals

```text
/goal Remote SSH transport and target resolution

Context:
Build Ryddi Remote Targets in Swift 6/SwiftPM. The feature must use system ssh, existing SSH config, no key storage, no password prompts, StrictHostKeyChecking=yes, and no destructive remote commands.

Deliverable:
Remote target models, SSH alias resolution, known_hosts status, and a fakeable safe SSH command runner with tests.

Boundaries:
Own RemoteTarget.swift and RemoteSSHCommandRunner.swift. Do not implement scan classification, UI, or docs.

Verification:
swift test --scratch-path "$PWD/.build" --filter RemoteTarget
swift test --scratch-path "$PWD/.build" --filter RemoteSSH
```

```text
/goal Remote VPS evidence scanning and parsers

Context:
Remote Targets v1 is report-only. It must gather bounded Linux VPS disk evidence for df/inodes, du, large files, journald, apt cache, and Docker inventory.

Deliverable:
RemoteProbe, RemoteParsers, RemoteScanBuilder, RemoteStorageFinding classification, and parser tests with fixture command output.

Boundaries:
Own probe/scan/parser core. Do not add CLI routing, SwiftUI, or audit store changes except types needed by this goal.

Verification:
swift test --scratch-path "$PWD/.build" --filter RemoteProbe
swift test --scratch-path "$PWD/.build" --filter RemoteScan
```

```text
/goal Remote native guidance and report export

Context:
Ryddi should recommend native cleanup commands for VPSes but must not execute them remotely in v1.

Deliverable:
RemoteNativeGuidanceBuilder and RemoteReportBuilder with Markdown/JSON-safe redaction and explicit non-claims.

Boundaries:
Own RemoteNativeGuidance.swift and RemoteReportExport.swift. Do not add remote execute support.

Verification:
swift test --scratch-path "$PWD/.build" --filter RemoteNative
swift test --scratch-path "$PWD/.build" --filter RemoteReport
```

```text
/goal Remote CLI and audit integration

Context:
Expose Remote Targets through the existing `reclaimer` CLI and local audit store, following current command/help conventions.

Deliverable:
`reclaimer remote targets list`, `probe`, `scan`, `native`, and `plan`; audit save/load for remote reports; blocked unsafe subcommands.

Boundaries:
Own main.swift remote dispatch and AuditStore additions. Do not change local cleanup behavior.

Verification:
swift run --scratch-path .build reclaimer remote targets list --json
swift test --scratch-path "$PWD/.build" --filter RemoteCLI
```

```text
/goal Remote Targets SwiftUI cockpit

Context:
The app should make remote rydding feel safe and understandable: probe first, scan next, review guidance, export evidence, no reclaim button.

Deliverable:
Remote Targets sidebar section, target input, probe/scan/report UI, cards for disk/host/native guidance, and remote non-claims.

Boundaries:
Own SwiftUI view/model changes. Do not add destructive remote action buttons.

Verification:
swift build --scratch-path "$PWD/.build"
Manual app smoke: Remote Targets opens, unsafe actions absent.
```

```text
/goal Remote docs privacy and release evidence

Context:
Remote Targets introduces SSH aliases, remote paths, host metadata, and command output previews, so privacy/non-claims must be precise.

Deliverable:
README, FEATURES, PRIVACY, docs/REMOTE_TARGETS.md, and competitive/release wording updates.

Boundaries:
Own docs only. Do not claim remote cleanup execution exists.

Verification:
rg -n "remote execute|StrictHostKeyChecking=no|password" README.md FEATURES.md PRIVACY.md docs
git diff --check
```

## Test Plan

- Unit: target parsing, `ssh -G` parsing, known_hosts state, safe SSH argv construction, timeout/output bounding, unsupported-host behavior.
- Unit: parser fixtures for `df -Pk`, `df -Pi`, GNU `du`, GNU `find`, `journalctl --disk-usage`, apt cache `du`, Docker `system df -v`, Docker object lists.
- Unit: classifications preserve Docker volumes, DB directories, `/etc`, credentials, backups, unknown app state, and user data.
- Unit: report redaction removes full remote paths in `redacted` mode and home prefix in `home-relative` mode.
- CLI: unsafe `remote execute/prune/reset` rejected; safe commands never prompt.
- Audit: remote probe/scan reports save and reload locally.
- Manual: optional real VPS read-only probe/scan only after user provides or confirms a target alias.

## Assumptions

- MVP target is Linux VPS over SSH; macOS/Windows remote cleanup is unsupported/degraded in this release.
- Existing SSH config and SSH agent are the user's responsibility; Ryddi does not manage keys.
- `sudo -n true` is a capability probe only; commands requiring sudo are guidance/manual unless a later release adds separately reviewed remote native execution.
- Docker and journald estimates are native-tool evidence, not exact APFS/ext4 reclaim promises.
