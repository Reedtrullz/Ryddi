# Ryddi Remote Dogfood Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only Remote Targets dogfood evidence package so Ryddi can safely exercise one real VPS alias, capture parser/classification gaps, and export a redacted report without signing, cleanup, or server mutation.

**Architecture:** Keep Remote Targets agentless and report-first. Add a core `RemoteDogfoodReport` that composes existing remote probe, remote scan, optional saved growth comparison, command receipts, coverage notes, privacy redaction, and explicit non-claims; expose it through CLI and SwiftUI without adding remote execution. Use fixtures and disposable audit records for automated verification, then run one optional user-approved live VPS smoke with strict read-only commands.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, macOS 14+, system `/usr/bin/ssh`, existing `ToolCommandRunning`, local JSON audit records, Markdown report export.

## Global Constraints

- Apple Developer team access is pending; do not claim a signed or notarized release.
- Before long build/test loops, run `df -h /System/Volumes/Data`; stop if free space is below `50Gi`.
- Use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"`.
- Remote dogfood is read-only: no `remote execute`, no raw deletes, no `prune`, no `reset`, no sudo cleanup, no package cleanup, no Docker cleanup.
- Use `/usr/bin/ssh` only through the existing safe remote runner: `BatchMode=yes`, `NumberOfPasswordPrompts=0`, `StrictHostKeyChecking=yes`, bounded timeout/output, and no requested agent forwarding.
- Do not store private keys, passwords, passphrases, sudo passwords, tokens, or remote secrets.
- Treat remote paths, Docker names, host aliases, and command previews as private; redacted exports must be shareable by default.
- Preserve Docker volumes, databases, backups, `/etc`, credentials, app data, unknown state, and remote user data by default.
- Automation and release-check smokes must use fake runners or disposable local audit JSON, never a real SSH target.
- Cleanup after work: remove `.build` and temp smoke files; keep only intentional `dist/` preview evidence if release-check ran.

---

## File Structure

- Create `Sources/ReclaimerCore/RemoteDogfoodReport.swift`
  - Owns `RemoteDogfoodReport`, `RemoteDogfoodReportBuilder`, Markdown rendering, redacted report composition, and non-claims.
- Modify `Sources/ReclaimerCore/AuditStore.swift`
  - Adds save/list/read helpers for remote dogfood reports and target-matched latest remote probe/scan lookup.
- Modify `Sources/reclaimer/main.swift`
  - Adds `reclaimer remote dogfood TARGET` and `reclaimer remote dogfood --from-audit TARGET`.
- Modify `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
  - Adds Remote Targets dogfood/export UI and recent dogfood report display.
- Modify `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`
  - Adds unit tests for dogfood report composition, redaction, audit round-trip, and CLI command rejection paths where possible.
- Modify `Scripts/release-check.sh`
  - Adds packaged CLI smoke for dogfood report generation from disposable saved remote audit records only.
- Modify `README.md`, `FEATURES.md`, `PRIVACY.md`, `docs/REMOTE_TARGETS.md`, `docs/RELEASE_CHECKLIST.md`
  - Documents dogfood evidence package, read-only remote scope, redaction limits, and unsigned-preview posture.

---

## Task 1: Baseline And Plan Commit

**Files:**
- Create: `docs/superpowers/plans/2026-07-07-ryddi-remote-dogfood-hardening.md`

**Interfaces:**
- Produces: repo-local implementation plan for remote dogfood hardening.

- [ ] **Step 1: Confirm disk headroom**

Run:

```bash
df -h /System/Volumes/Data
```

Expected: available space is at least `50Gi`.

- [ ] **Step 2: Confirm branch state**

Run:

```bash
git status --short --branch
git log -1 --oneline
```

Expected: branch is `feature/remote-targets`; any existing changes are only this plan file.

- [ ] **Step 3: Run baseline tests**

Run:

```bash
swift test --scratch-path "$PWD/.build"
```

Expected: current full suite passes before dogfood changes.

- [ ] **Step 4: Commit the plan**

Run:

```bash
git add docs/superpowers/plans/2026-07-07-ryddi-remote-dogfood-hardening.md
git commit -m "docs: plan remote dogfood hardening"
```

Expected: plan-only commit. Do not push if later tasks will be committed immediately in the same branch slice.

---

## Task 2: Core Remote Dogfood Report

**Files:**
- Create: `Sources/ReclaimerCore/RemoteDogfoodReport.swift`
- Modify: `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`

**Interfaces:**
- Consumes: `RemoteProbeReport`, `RemoteScanReport`, `RemoteGrowthReport`, `RemoteCommandResult`, `ReportPrivacyOptions`.
- Produces:
  - `public struct RemoteDogfoodReport: Codable, Hashable, Identifiable, Sendable`
  - `public enum RemoteDogfoodReportBuilder`
  - `public static func build(probe: RemoteProbeReport?, scan: RemoteScanReport, growth: RemoteGrowthReport?, privacy: ReportPrivacyOptions, now: Date) -> RemoteDogfoodReport`

- [ ] **Step 1: Write failing report composition test**

Add this test near the other Remote Targets tests:

```swift
func testRemoteDogfoodReportComposesScanGrowthAndRedactsPaths() throws {
    let target = RemoteTargetReference(
        input: "prod-vps",
        alias: "prod-vps",
        resolvedUser: "deploy",
        resolvedHost: "203.0.113.10",
        resolvedPort: 22,
        knownHostsState: "known",
        fingerprint: "ssh-ed25519:fixture"
    )
    let probe = RemoteProbeReport(
        id: "probe-1",
        createdAt: Date(timeIntervalSince1970: 10),
        target: target,
        osSummary: "Ubuntu 24.04 LTS",
        homeDirectory: "/home/deploy",
        sudoNonInteractive: false,
        availableTools: ["docker", "journalctl"],
        commands: [
            RemoteCommandResult(
                commandID: "probe.uname",
                displayCommand: "uname -srm",
                exitCode: 0,
                timedOut: false,
                stdoutPreview: ["Linux 6.8.0 x86_64"],
                stderrPreview: [],
                redactionApplied: false
            )
        ],
        nonClaims: RemoteProbeReport.defaultNonClaims
    )
    let scan = RemoteScanReport(
        id: "scan-1",
        createdAt: Date(timeIntervalSince1970: 20),
        preset: .vpsGeneral,
        target: target,
        diskFilesystems: [
            RemoteFilesystemSummary(mount: "/", filesystem: "/dev/vda1", usedBytes: 80_000, availableBytes: 20_000, capacityPercent: 80)
        ],
        inodeFilesystems: [],
        findings: [
            RemoteStorageFinding(
                remotePath: "/home/deploy/private-client/cache",
                displayPath: "/home/deploy/private-client/cache",
                bucket: "Remote storage",
                allocatedBytes: 180,
                safetyClass: .reviewRequired,
                actionKind: .openGuidance,
                evidence: [Evidence(kind: "remote.fixture", message: "Fixture evidence.")],
                recommendedNextAction: .reviewInFinder
            )
        ],
        nativeGuidance: [],
        commands: [],
        nonClaims: RemoteScanReport.defaultNonClaims
    )
    let growth = RemoteGrowthReportBuilder.build(
        previous: scan,
        current: scan,
        privacy: ReportPrivacyOptions(pathStyle: .redacted),
        now: Date(timeIntervalSince1970: 30)
    )

    let report = RemoteDogfoodReportBuilder.build(
        probe: probe,
        scan: scan,
        growth: growth,
        privacy: ReportPrivacyOptions(pathStyle: .redacted),
        now: Date(timeIntervalSince1970: 40)
    )

    XCTAssertEqual(report.target.id, target.id)
    XCTAssertEqual(report.scanID, "scan-1")
    XCTAssertEqual(report.probeID, "probe-1")
    XCTAssertEqual(report.findingCount, 1)
    XCTAssertEqual(report.totalFindingBytes, 180)
    XCTAssertTrue(report.markdown.contains("# Ryddi Remote Dogfood Report"))
    XCTAssertTrue(report.markdown.contains("Ubuntu 24.04 LTS"))
    XCTAssertTrue(report.markdown.contains("<path redacted>"))
    XCTAssertFalse(report.markdown.contains("private-client"))
    XCTAssertTrue(report.nonClaims.contains { $0.contains("No cleanup was executed") })
    XCTAssertTrue(report.nonClaims.contains { $0.contains("read-only") })
    XCTAssertTrue(report.nonClaims.contains { $0.contains("does not prove current server state") })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteDogfood
```

Expected: compile failure because `RemoteDogfoodReportBuilder` does not exist.

- [ ] **Step 3: Implement core model and builder**

Create `Sources/ReclaimerCore/RemoteDogfoodReport.swift`:

```swift
import Foundation

public struct RemoteDogfoodReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let target: RemoteTargetReference
    public let probeID: String?
    public let scanID: String
    public let growthReportID: String?
    public let osSummary: String?
    public let diskPressureSummary: String
    public let findingCount: Int
    public let totalFindingBytes: Int64
    public let reviewQueueCounts: [String: Int]
    public let commandResults: [RemoteCommandResult]
    public let nonClaims: [String]
    public let markdown: String

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        target: RemoteTargetReference,
        probeID: String?,
        scanID: String,
        growthReportID: String?,
        osSummary: String?,
        diskPressureSummary: String,
        findingCount: Int,
        totalFindingBytes: Int64,
        reviewQueueCounts: [String: Int],
        commandResults: [RemoteCommandResult],
        nonClaims: [String],
        markdown: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.target = target
        self.probeID = probeID
        self.scanID = scanID
        self.growthReportID = growthReportID
        self.osSummary = osSummary
        self.diskPressureSummary = diskPressureSummary
        self.findingCount = findingCount
        self.totalFindingBytes = totalFindingBytes
        self.reviewQueueCounts = reviewQueueCounts
        self.commandResults = commandResults
        self.nonClaims = nonClaims
        self.markdown = markdown
    }
}

public enum RemoteDogfoodReportBuilder {
    public static func build(
        probe: RemoteProbeReport?,
        scan: RemoteScanReport,
        growth: RemoteGrowthReport?,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> RemoteDogfoodReport {
        let bytes = scan.findings.reduce(Int64(0)) { $0 + ($1.allocatedBytes ?? 0) }
        let queueCounts = Dictionary(grouping: scan.findings, by: { $0.recommendedNextAction.rawValue })
            .mapValues(\.count)
        let commands = (probe?.commands ?? []) + scan.commands
        var nonClaims = [
            "No cleanup was executed on the remote target.",
            "Remote dogfood is read-only and uses bounded probe/scan evidence.",
            "This report does not prove current server state after the scan time.",
            "This report does not prove exact reclaimable bytes or cleanup safety.",
            "Ryddi did not store SSH private keys, passwords, passphrases, sudo passwords, tokens, or remote secrets."
        ]
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local audit JSON may still contain original remote paths.")
        }
        let report = RemoteDogfoodReport(
            createdAt: now,
            target: scan.target,
            probeID: probe?.id,
            scanID: scan.id,
            growthReportID: growth?.id,
            osSummary: probe?.osSummary,
            diskPressureSummary: diskPressureSummary(scan.diskFilesystems),
            findingCount: scan.findings.count,
            totalFindingBytes: bytes,
            reviewQueueCounts: queueCounts,
            commandResults: commands,
            nonClaims: nonClaims,
            markdown: ""
        )
        return RemoteDogfoodReport(
            id: report.id,
            createdAt: report.createdAt,
            target: report.target,
            probeID: report.probeID,
            scanID: report.scanID,
            growthReportID: report.growthReportID,
            osSummary: report.osSummary,
            diskPressureSummary: report.diskPressureSummary,
            findingCount: report.findingCount,
            totalFindingBytes: report.totalFindingBytes,
            reviewQueueCounts: report.reviewQueueCounts,
            commandResults: report.commandResults,
            nonClaims: report.nonClaims,
            markdown: markdown(for: report, scan: scan, growth: growth, privacy: privacy)
        )
    }

    private static func diskPressureSummary(_ filesystems: [RemoteFilesystemSummary]) -> String {
        guard let max = filesystems.compactMap(\.capacityPercent).max() else { return "Unknown" }
        return "\(max)% max filesystem capacity"
    }

    private static func markdown(
        for report: RemoteDogfoodReport,
        scan: RemoteScanReport,
        growth: RemoteGrowthReport?,
        privacy: ReportPrivacyOptions
    ) -> String {
        var lines: [String] = []
        lines.append("# Ryddi Remote Dogfood Report")
        lines.append("")
        lines.append("- Target: \(report.target.alias ?? report.target.input)")
        lines.append("- Host: \(report.target.resolvedHost ?? "unknown")")
        lines.append("- OS: \(report.osSummary ?? "unknown")")
        lines.append("- Disk pressure: \(report.diskPressureSummary)")
        lines.append("- Findings: \(report.findingCount)")
        lines.append("- Finding bytes: \(ByteFormat.string(report.totalFindingBytes))")
        lines.append("")
        lines.append("## Largest Findings")
        for finding in scan.findings.sorted(by: { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }).prefix(10) {
            lines.append("- \(ByteFormat.string(finding.allocatedBytes ?? 0)) \(finding.bucket): `\(privacy.displayPath(finding.remotePath))`")
        }
        if let growth {
            lines.append("")
            lines.append("## Saved Growth Signal")
            lines.append("- Compared scans: `\(growth.previousScanID)` -> `\(growth.currentScanID)`")
            lines.append("- Delta: \(growth.deltaAllocatedBytes > 0 ? "+" : "")\(ByteFormat.string(growth.deltaAllocatedBytes))")
        }
        lines.append("")
        lines.append("## Command Receipts")
        for command in report.commandResults.prefix(20) {
            lines.append("- `\(command.commandID)`: exit \(command.exitCode.map(String.init) ?? "unknown"), timedOut=\(command.timedOut)")
        }
        lines.append("")
        lines.append("## Explicit Non-Claims")
        for note in report.nonClaims {
            lines.append("- \(note)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run focused test**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteDogfood
```

Expected: focused dogfood test passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/ReclaimerCore/RemoteDogfoodReport.swift Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift
git commit -m "feat: add remote dogfood report"
```

---

## Task 3: Remote Dogfood Audit Storage

**Files:**
- Modify: `Sources/ReclaimerCore/AuditStore.swift`
- Modify: `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`

**Interfaces:**
- Consumes: `RemoteDogfoodReport`.
- Produces:
  - `public func save(remoteDogfoodReport report: RemoteDogfoodReport) throws -> URL`
  - `public func recentRemoteDogfoodReports(limit: Int = 20) -> [RemoteDogfoodReport]`
  - `public func latestRemoteScanReport(matching target: RemoteTargetReference) -> RemoteScanReport?`
  - `public func latestRemoteProbeReport(matching target: RemoteTargetReference) -> RemoteProbeReport?`

- [ ] **Step 1: Write failing audit round-trip test**

Add:

```swift
func testAuditStoreRoundTripsRemoteDogfoodReportsAndFindsLatestTargetEvidence() throws {
    let root = try temporaryDirectory()
    let store = AuditStore(root: root)
    let target = RemoteTargetReference(
        input: "prod-vps",
        alias: "prod-vps",
        resolvedUser: "deploy",
        resolvedHost: "203.0.113.10",
        resolvedPort: 22,
        knownHostsState: "known",
        fingerprint: "ssh-ed25519:fixture"
    )
    let scan = RemoteScanReport(
        id: "scan-1",
        createdAt: Date(timeIntervalSince1970: 20),
        preset: .vpsGeneral,
        target: target,
        diskFilesystems: [],
        inodeFilesystems: [],
        findings: [],
        nativeGuidance: [],
        commands: [],
        nonClaims: RemoteScanReport.defaultNonClaims
    )
    let probe = RemoteProbeReport(
        id: "probe-1",
        createdAt: Date(timeIntervalSince1970: 10),
        target: target,
        osSummary: "Ubuntu",
        homeDirectory: "/home/deploy",
        sudoNonInteractive: false,
        availableTools: [],
        commands: [],
        nonClaims: RemoteProbeReport.defaultNonClaims
    )
    try store.save(remoteProbeReport: probe)
    try store.save(remoteScanReport: scan)
    let dogfood = RemoteDogfoodReportBuilder.build(probe: probe, scan: scan, growth: nil)
    try store.save(remoteDogfoodReport: dogfood)

    XCTAssertEqual(store.recentRemoteDogfoodReports().first?.id, dogfood.id)
    XCTAssertEqual(store.latestRemoteScanReport(matching: target)?.id, scan.id)
    XCTAssertEqual(store.latestRemoteProbeReport(matching: target)?.id, probe.id)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStoreRoundTripsRemoteDogfood
```

Expected: compile failure for missing audit methods.

- [ ] **Step 3: Implement audit methods**

Add methods near existing remote audit helpers in `AuditStore.swift`:

```swift
@discardableResult
public func save(remoteDogfoodReport report: RemoteDogfoodReport) throws -> URL {
    let url = root.appendingPathComponent("remote-dogfood-\(report.id).json")
    try write(report, to: url)
    return url
}

public func recentRemoteDogfoodReports(limit: Int = 20) -> [RemoteDogfoodReport] {
    guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
        return []
    }
    return files
        .filter { $0.lastPathComponent.hasPrefix("remote-dogfood-") && $0.pathExtension == "json" }
        .sorted(by: newestFirst)
        .prefix(limit)
        .compactMap { try? decoder.decode(RemoteDogfoodReport.self, from: Data(contentsOf: $0)) }
}

public func latestRemoteScanReport(matching target: RemoteTargetReference) -> RemoteScanReport? {
    recentRemoteScanReports(limit: Int.max).first { remoteTargetsMatch($0.target, target) }
}

public func latestRemoteProbeReport(matching target: RemoteTargetReference) -> RemoteProbeReport? {
    recentRemoteProbeReports(limit: Int.max).first { remoteTargetsMatch($0.target, target) }
}

private func remoteTargetsMatch(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
    lhs.id == rhs.id || (lhs.resolvedHost == rhs.resolvedHost && lhs.resolvedUser == rhs.resolvedUser && lhs.resolvedPort == rhs.resolvedPort)
}
```

If `newestFirst` is not visible in this scope, follow the existing `AuditStore` sorting helper pattern instead of introducing a second sorter.

- [ ] **Step 4: Run focused test**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStoreRoundTripsRemoteDogfood
```

Expected: test passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/ReclaimerCore/AuditStore.swift Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift
git commit -m "feat: persist remote dogfood reports"
```

---

## Task 4: CLI Remote Dogfood Command

**Files:**
- Modify: `Sources/reclaimer/main.swift`
- Modify: `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`

**Interfaces:**
- Consumes: `RemoteDogfoodReportBuilder`, `AuditStore`, `RemoteTargetResolver`, `RemoteProbeBuilder`, `RemoteScanBuilder`.
- Produces:
  - `reclaimer remote dogfood TARGET [--json] [--timeout SECONDS] [--path-style full|home-relative|redacted] [--output FILE] [--save-audit]`
  - `reclaimer remote dogfood --from-audit TARGET [--json] [--path-style ...] [--output FILE] [--save-audit]`

- [ ] **Step 1: Add CLI rejection/usage tests where possible**

If the test target can call `ReclaimerCLI.run(arguments:)`, add:

```swift
func testRemoteDogfoodHelpRejectsUnsafeSubcommands() throws {
    XCTAssertThrowsError(try ReclaimerCLI.run(arguments: ["remote", "execute", "prod-vps"])) { error in
        XCTAssertTrue(error.localizedDescription.contains("report-only"))
    }
    XCTAssertThrowsError(try ReclaimerCLI.run(arguments: ["remote", "prune", "prod-vps"])) { error in
        XCTAssertTrue(error.localizedDescription.contains("report-only"))
    }
}
```

If `ReclaimerCLI` is not test-visible, keep this as a packaged smoke in Task 7.

- [ ] **Step 2: Add dispatch and help**

In `remote(args:)`, add:

```swift
case "dogfood":
    try remoteDogfood(args: rest)
```

In help text, add:

```text
remote dogfood TARGET [--json] [--timeout SECONDS] [--path-style full|home-relative|redacted] [--output PATH] [--save-audit]
remote dogfood --from-audit TARGET [--json] [--path-style full|home-relative|redacted] [--output PATH] [--save-audit]
```

- [ ] **Step 3: Implement `remoteDogfood(args:)`**

Add near other remote CLI methods:

```swift
static func remoteDogfood(args: [String]) throws {
    let options = ParsedOptions(args)
    try options.validateReportPrivacyOptions()
    guard let targetInput = remoteTargetArgument(args) else {
        throw CLIError.message("remote dogfood requires TARGET")
    }
    let store = AuditStore()
    let target = try RemoteTargetResolver().resolve(targetInput)
    let probe: RemoteProbeReport?
    let scan: RemoteScanReport
    if args.contains("--from-audit") {
        guard let latestScan = store.latestRemoteScanReport(matching: target) else {
            throw CLIError.message("remote dogfood --from-audit found no saved remote scan for \(targetInput)")
        }
        scan = latestScan
        probe = store.latestRemoteProbeReport(matching: target)
    } else {
        probe = try RemoteProbeBuilder(target: target, timeout: options.timeoutSeconds).probe()
        scan = RemoteScanBuilder(target: target, timeout: options.timeoutSeconds).scan(
            preset: try options.remoteScanPreset(),
            privacy: options.reportPrivacy
        )
    }
    let previous = store.recentRemoteScanReports(limit: Int.max)
        .first { $0.id != scan.id && $0.target.id == scan.target.id }
    let growth = previous.map {
        RemoteGrowthReportBuilder.build(previous: $0, current: scan, privacy: options.reportPrivacy)
    }
    let report = RemoteDogfoodReportBuilder.build(
        probe: probe,
        scan: scan,
        growth: growth,
        privacy: options.reportPrivacy
    )
    if options.saveAudit {
        let url = try store.save(remoteDogfoodReport: report)
        FileHandle.standardError.write(Data("saved remote dogfood report: \(url.path)\n".utf8))
    }
    if let output = options.outputPath {
        let url = URL(fileURLWithPath: output).standardizedFileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.markdown.write(to: url, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("wrote remote dogfood report: \(url.path)\n".utf8))
    }
    if options.json {
        printJSON(report)
    } else if options.outputPath == nil {
        print(report.markdown)
    }
}
```

- [ ] **Step 4: Run CLI build**

Run:

```bash
swift build --scratch-path "$PWD/.build"
```

Expected: build passes.

- [ ] **Step 5: Run no-prompt unknown target smoke**

Run:

```bash
swift run --scratch-path .build reclaimer remote dogfood definitely-not-a-real-ryddi-host --timeout 1 --json
```

Expected: exits non-zero quickly without a password prompt. The error should mention read-only SSH/probe failure, not cleanup.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/reclaimer/main.swift Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift
git commit -m "feat: add remote dogfood cli"
```

---

## Task 5: SwiftUI Remote Dogfood Cockpit

**Files:**
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`

**Interfaces:**
- Consumes: `RemoteDogfoodReport`, `RemoteDogfoodReportBuilder`, `AuditStore.recentRemoteDogfoodReports`.
- Produces:
  - `DashboardModel.remoteDogfoodReport`
  - `DashboardModel.lastRemoteDogfoodReportExportURL`
  - `DashboardModel.exportRemoteDogfoodReportFromAudit()`
  - Remote Targets UI section titled `Dogfood Evidence`

- [ ] **Step 1: Add model state**

Add alongside other remote model properties:

```swift
var remoteDogfoodReport: RemoteDogfoodReport?
var recentRemoteDogfoodReports: [RemoteDogfoodReport] = []
var lastRemoteDogfoodReportExportURL: URL?
```

- [ ] **Step 2: Load recent dogfood audit**

In `loadAudit()`, add:

```swift
recentRemoteDogfoodReports = store.recentRemoteDogfoodReports()
if remoteDogfoodReport == nil {
    remoteDogfoodReport = recentRemoteDogfoodReports.first
}
```

- [ ] **Step 3: Add export-from-audit action**

Add:

```swift
func exportRemoteDogfoodReportFromAudit() async {
    guard let scan = recentRemoteScanReports.first else {
        error = "Remote dogfood export needs at least one saved remote scan."
        return
    }
    let probe = recentRemoteProbeReports.first { $0.target.id == scan.target.id }
    let previous = recentRemoteScanReports.dropFirst().first { $0.target.id == scan.target.id }
    isWorking = true
    defer { isWorking = false }
    do {
        let report = RemoteDogfoodReportBuilder.build(
            probe: probe,
            scan: scan,
            growth: previous.map { RemoteGrowthReportBuilder.build(previous: $0, current: scan, privacy: ReportPrivacyOptions(pathStyle: .redacted)) },
            privacy: ReportPrivacyOptions(pathStyle: .redacted)
        )
        let url = try await Task.detached {
            let root = ReportStore.defaultRoot()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("remote-dogfood-\(report.id).md")
            try report.markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        }.value
        remoteDogfoodReport = report
        lastRemoteDogfoodReportExportURL = url
        error = nil
    } catch {
        self.error = error.localizedDescription
    }
}
```

- [ ] **Step 4: Add Remote Targets UI section**

In `RemoteTargetsView`, add a button beside existing export buttons:

```swift
Button {
    Task { await model.exportRemoteDogfoodReportFromAudit() }
} label: {
    Label("Dogfood Report", systemImage: "doc.text.magnifyingglass")
}
.disabled(model.recentRemoteScanReports.isEmpty || model.isWorking)
```

Add a section when `remoteDogfoodReport` exists:

```swift
if let dogfood = model.remoteDogfoodReport {
    SectionBox(title: "Dogfood Evidence") {
        HStack(spacing: 16) {
            MetricTile(title: "Findings", value: "\(dogfood.findingCount)")
            MetricTile(title: "Finding bytes", value: ByteFormat.string(dogfood.totalFindingBytes))
            MetricTile(title: "Commands", value: "\(dogfood.commandResults.count)")
            MetricTile(title: "Disk pressure", value: dogfood.diskPressureSummary)
        }
        Text("Built from read-only remote evidence. It does not run cleanup or reconnect when exported from saved audit.")
            .font(.caption)
            .foregroundStyle(.secondary)
        ForEach(dogfood.nonClaims.prefix(5), id: \.self) { note in
            Text("• \(note)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 5: Build app target**

Run:

```bash
swift build --scratch-path "$PWD/.build"
```

Expected: build passes.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift
git commit -m "feat: surface remote dogfood evidence"
```

---

## Task 6: Parser Fixture Hardening

**Files:**
- Create: `Tests/ReclaimerCoreTests/Fixtures/remote-ubuntu-24-docker.txt`
- Create: `Tests/ReclaimerCoreTests/Fixtures/remote-debian-minimal.txt`
- Modify: `Sources/ReclaimerCore/RemoteParsers.swift`
- Modify: `Sources/ReclaimerCore/RemoteScan.swift`
- Modify: `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`

**Interfaces:**
- Consumes: existing `RemoteParsers` and `RemoteScanBuilder` parser functions.
- Produces: parser coverage for common Linux VPS variants before real target dogfood.

- [ ] **Step 1: Add Ubuntu fixture**

Create `Tests/ReclaimerCoreTests/Fixtures/remote-ubuntu-24-docker.txt`:

```text
### df -Pk
Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/vda1        41151808 32309216   6710892      83% /
overlay          41151808 32309216   6710892      83% /var/lib/docker/overlay2/abc/merged

### df -Pi
Filesystem      Inodes  IUsed   IFree IUse% Mounted on
/dev/vda1      2621440 310000 2311440   12% /

### du -k
1048576 /var/log
2097152 /var/lib/docker
524288 /home/deploy/releases

### journalctl --disk-usage
Archived and active journals take up 768.0M in the file system.

### apt cache du
256000 /var/cache/apt

### docker system df -v
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          12        4         3.4GB     1.1GB (32%)
Containers      8         3         820MB     400MB (48%)
Local Volumes   6         6         9.8GB     0B (0%)
Build Cache     44        0         2.2GB     2.2GB
```

- [ ] **Step 2: Add Debian minimal fixture**

Create `Tests/ReclaimerCoreTests/Fixtures/remote-debian-minimal.txt`:

```text
### df -Pk
Filesystem     1024-blocks    Used Available Capacity Mounted on
/dev/sda1       20511356 9980000   9460000      52% /

### df -Pi
Filesystem      Inodes IUsed   IFree IUse% Mounted on
/dev/sda1      1310720 45000 1265720    4% /

### du -k
65536 /var/log
131072 /home/admin

### journalctl --disk-usage
No journal files were found.

### apt cache du
4096 /var/cache/apt

### docker system df -v
docker: command not found
```

- [ ] **Step 3: Add fixture parser tests**

Add:

```swift
func testRemoteParserFixturesHandleUbuntuDockerAndDebianMinimal() throws {
    let ubuntu = try fixtureText("remote-ubuntu-24-docker.txt")
    XCTAssertTrue(ubuntu.contains("3.4GB"))
    let ubuntuFilesystems = RemoteParsers.parseDiskFilesystems(section("df -Pk", in: ubuntu))
    XCTAssertEqual(ubuntuFilesystems.first?.capacityPercent, 83)
    let ubuntuJournal = RemoteParsers.parseJournalDiskUsage(section("journalctl --disk-usage", in: ubuntu))
    XCTAssertEqual(ubuntuJournal, 805_306_368)

    let debian = try fixtureText("remote-debian-minimal.txt")
    let debianFilesystems = RemoteParsers.parseDiskFilesystems(section("df -Pk", in: debian))
    XCTAssertEqual(debianFilesystems.first?.capacityPercent, 52)
    let debianJournal = RemoteParsers.parseJournalDiskUsage(section("journalctl --disk-usage", in: debian))
    XCTAssertEqual(debianJournal, 0)
}
```

If fixture helpers do not exist, add private helpers in the test file:

```swift
private func fixtureText(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try String(contentsOf: url, encoding: .utf8)
}

private func section(_ title: String, in text: String) -> String {
    let marker = "### \(title)"
    guard let start = text.range(of: marker) else { return "" }
    let rest = text[start.upperBound...]
    if let end = rest.range(of: "\n### ") {
        return String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return rest.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

- [ ] **Step 4: Run parser tests**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteParser
```

Expected: parser fixtures pass. If they fail, fix parser functions only for the observed fixture shape.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/ReclaimerCore/RemoteParsers.swift Sources/ReclaimerCore/RemoteScan.swift Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift Tests/ReclaimerCoreTests/Fixtures
git commit -m "test: harden remote parser fixtures"
```

---

## Task 7: Release-Check And Docs

**Files:**
- Modify: `Scripts/release-check.sh`
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `PRIVACY.md`
- Modify: `docs/REMOTE_TARGETS.md`
- Modify: `docs/RELEASE_CHECKLIST.md`

**Interfaces:**
- Consumes: `reclaimer remote dogfood --from-audit`.
- Produces: packaged CLI proof that dogfood report export can be built from disposable saved remote audit records without SSH.

- [ ] **Step 1: Add release-check disposable remote dogfood smoke**

After the existing remote history smoke in `Scripts/release-check.sh`, add:

```bash
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" remote dogfood --from-audit prod-vps --path-style redacted --output "$scratch/remote-dogfood-report.md"
grep -q "# Ryddi Remote Dogfood Report" "$scratch/remote-dogfood-report.md"
grep -q "No cleanup was executed" "$scratch/remote-dogfood-report.md"
grep -q "<path redacted>" "$scratch/remote-dogfood-report.md"
if grep -q "private-client" "$scratch/remote-dogfood-report.md"; then
  echo "remote dogfood report leaked redacted path component" >&2
  exit 1
fi
```

Add this manifest bullet:

```text
- bundled reclaimer remote dogfood --from-audit on disposable saved remote audit records, with redacted Markdown and no SSH connection
```

- [ ] **Step 2: Update README remote section**

Add:

```markdown
Remote dogfood evidence packages can be created from a live read-only scan or from saved audit records:

```bash
swift run --scratch-path .build reclaimer remote dogfood my-vps --path-style redacted --output ryddi-vps-dogfood.md --save-audit
swift run --scratch-path .build reclaimer remote dogfood --from-audit my-vps --path-style redacted --output ryddi-vps-dogfood.md
```

`--from-audit` does not reconnect to the server. It compares and packages saved local evidence only.
```

- [ ] **Step 3: Update privacy wording**

Add:

```markdown
Remote dogfood reports can combine remote probe metadata, remote scan findings, command previews, saved growth deltas, and redacted remote paths. Redaction affects the exported Markdown report; saved local audit JSON can still contain original remote paths and host metadata.
```

- [ ] **Step 4: Update feature and checklist docs**

Add one bullet to `FEATURES.md` proof section:

```markdown
- `reclaimer remote dogfood --from-audit TARGET --path-style redacted --output FILE.md` packages saved remote evidence without reconnecting to a server or running cleanup.
```

Add one checklist item:

```markdown
- [ ] `reclaimer remote dogfood --from-audit` writes redacted Markdown from disposable saved remote audit records and does not connect to or mutate a server.
```

- [ ] **Step 5: Run docs scan**

Run:

```bash
rg -n "remote dogfood|--from-audit|remote execute|StrictHostKeyChecking=no|password" README.md FEATURES.md PRIVACY.md docs
```

Expected: dogfood appears in docs; unsafe remote execution/password patterns appear only as blocked/non-goal language.

- [ ] **Step 6: Commit**

Run:

```bash
git add Scripts/release-check.sh README.md FEATURES.md PRIVACY.md docs/REMOTE_TARGETS.md docs/RELEASE_CHECKLIST.md
git commit -m "docs: document remote dogfood evidence"
```

---

## Task 8: Optional Real VPS Read-Only Dogfood Protocol

**Files:**
- No source files required unless parser gaps are found.
- Output: user-selected local Markdown path, for example `/tmp/ryddi-vps-dogfood-redacted.md`.

**Interfaces:**
- Consumes: user-approved SSH alias that already works with the user's SSH config.
- Produces: redacted dogfood report and list of any parser/classification follow-up issues.

- [ ] **Step 1: Ask for one explicit target alias**

Ask:

```text
Which SSH alias should I use for a read-only Ryddi Remote Targets dogfood run?
```

Do not guess a host. Do not enumerate private hosts in the final answer unless the user has already exposed the alias in this thread.

- [ ] **Step 2: Run safe target list**

Run:

```bash
swift run --scratch-path .build reclaimer remote targets list --json
```

Expected: command reads local SSH config only and does not connect.

- [ ] **Step 3: Probe approved target**

Run, replacing `ALIAS`:

```bash
swift run --scratch-path .build reclaimer remote probe ALIAS --json --timeout 5 --save-audit > /tmp/ryddi-remote-probe.json
```

Expected: exits `0` or fails without password prompt. If it fails, stop and report the failure; do not weaken SSH options.

- [ ] **Step 4: Scan approved target**

Run:

```bash
swift run --scratch-path .build reclaimer remote scan ALIAS --preset vps-general --path-style redacted --timeout 10 --output /tmp/ryddi-remote-scan.md --save-audit
```

Expected: exits `0` or fails safely. No cleanup command runs.

- [ ] **Step 5: Export dogfood report**

Run:

```bash
swift run --scratch-path .build reclaimer remote dogfood --from-audit ALIAS --path-style redacted --output /tmp/ryddi-vps-dogfood-redacted.md --save-audit
```

Expected: report contains `# Ryddi Remote Dogfood Report`, `Explicit Non-Claims`, and no obvious full private path components.

- [ ] **Step 6: Convert gaps into tests**

If parser/classification output is wrong, create a sanitized fixture with only the minimal failing command output and add a focused test before changing code. Commit as:

```bash
git add Sources/ReclaimerCore/RemoteParsers.swift Sources/ReclaimerCore/RemoteScan.swift Tests/ReclaimerCoreTests
git commit -m "fix: harden remote dogfood parser gap"
```

- [ ] **Step 7: Delete raw temp JSON if it contains private details**

Run:

```bash
rm -f /tmp/ryddi-remote-probe.json
```

Keep the redacted Markdown only if the user wants it retained.

---

## Task 9: Final Verification And Push

**Files:**
- All changed files from prior tasks.

**Interfaces:**
- Produces: pushed `feature/remote-targets` branch with local proof, unsigned preview proof, and explicit non-claims.

- [ ] **Step 1: Run full tests**

Run:

```bash
df -h /System/Volumes/Data
swift test --scratch-path "$PWD/.build"
```

Expected: disk headroom above `50Gi`; all tests pass.

- [ ] **Step 2: Run build and release-check**

Run:

```bash
swift build --scratch-path "$PWD/.build"
Scripts/release-check.sh
git diff --check
```

Expected: all pass; manifest says unsigned developer preview unless signing credentials are configured.

- [ ] **Step 3: Confirm no signing claim**

Run:

```bash
rg -n "signed and notarized|v0\\.2\\.0" README.md FEATURES.md docs/RELEASE_CHECKLIST.md dist/Ryddi-release-manifest.txt
```

Expected: signed/notarized language remains conditional on release manifest proof. `dist/Ryddi-release-manifest.txt` says unsigned developer preview while Apple Developer team access is pending.

- [ ] **Step 4: Push branch**

Run:

```bash
git status --short --branch
git push origin feature/remote-targets
```

Expected: branch pushed; worktree clean.

- [ ] **Step 5: Check GitHub Actions**

Run:

```bash
gh run list --repo Reedtrullz/Ryddi --branch feature/remote-targets --limit 5 --json databaseId,status,conclusion,headSha,url
```

Expected: record any visible CI result. If no runs are visible, say CI is unclaimed.

- [ ] **Step 6: Cleanup autonomous build artifacts**

Run:

```bash
rm -rf .build
setopt null_glob
leftovers=(/private/tmp/[Vv]ifty* /private/tmp/[Rr]yddi*)
if (( ${#leftovers[@]} )); then du -sh $leftovers; else print 'No Vifty/Ryddi leftovers found in /private/tmp'; fi
du -sh . dist 2>/dev/null || true
df -h /System/Volumes/Data
```

Expected: `.build` removed; no unexpected temp leftovers. Keep `dist/` only if release-check evidence is useful.

---

## Acceptance Criteria

- `reclaimer remote dogfood --from-audit TARGET --path-style redacted --output FILE.md` works using disposable saved audit records and does not open SSH.
- `reclaimer remote dogfood TARGET` uses only existing safe read-only probe/scan commands.
- Dogfood Markdown includes target summary, OS/disk pressure when known, largest findings, optional saved growth, command receipts, and explicit non-claims.
- Redacted dogfood reports do not leak known private fixture path components.
- SwiftUI Remote Targets has a dogfood evidence/export surface and no remote cleanup controls.
- Release-check proves dogfood export from disposable audit records without connecting to a server.
- Full local tests/build/release-check pass before pushing.
- Signed/notarized release remains unclaimed until Apple Developer team access and release signing gates pass.

## Execution Recommendation

Use subagent-driven execution if multiple workers are available:

- Worker 1: Core `RemoteDogfoodReport` plus audit store tests.
- Worker 2: CLI dispatch and release-check smoke.
- Worker 3: SwiftUI Remote Targets dogfood surface.
- Worker 4: Fixture parser hardening and docs.

If executing inline, do Tasks 2-4 first because they establish the core proof path, then Task 5 UI, then Tasks 6-9.
