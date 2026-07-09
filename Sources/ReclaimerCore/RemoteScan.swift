import Foundation

public struct RemoteMarkdownReport: Codable, Hashable, Sendable {
    public let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }
}

public final class RemoteScanBuilder: @unchecked Sendable {
    public static let scanCommands: [(id: String, command: String)] = [
        ("scan.df", "df -Pk"),
        ("scan.inodes", "df -Pi"),
        ("scan.du", "du -k -d 1 /var /home /opt /srv /tmp /var/tmp /var/log /var/lib 2>/dev/null"),
        ("scan.large-files", "find /var /home /opt /srv -xdev -type f -size +1024M -printf '%s\\t%p\\n' 2>/dev/null | sort -nr | head -50"),
        ("scan.journal", "journalctl --disk-usage"),
        ("scan.apt", "du -sk /var/cache/apt/archives 2>/dev/null"),
        ("scan.docker-df", "docker system df -v"),
        ("scan.docker-containers", "docker ps -a --size --format '{{.ID}}\\t{{.Names}}\\t{{.Status}}\\t{{.Size}}'"),
        ("scan.docker-images", "docker images --format '{{.Repository}}\\t{{.Tag}}\\t{{.ID}}\\t{{.Size}}'"),
        ("scan.docker-volumes", "docker volume ls --format '{{.Name}}\\t{{.Driver}}\\t{{.Scope}}'")
    ]

    private let target: RemoteTargetReference
    private let ssh: RemoteSSHCommandRunner

    public init(target: RemoteTargetReference, runner: any ToolCommandRunning = ProcessToolCommandRunner(), timeout: TimeInterval = 15) {
        self.target = target
        self.ssh = RemoteSSHCommandRunner(
            target: target,
            runner: runner,
            timeout: timeout,
            connectTimeout: max(1, min(Int(timeout.rounded(.up)), 10))
        )
    }

    public func scan(preset: RemoteScanPreset = .vpsGeneral, privacy: ReportPrivacyOptions = .default) -> RemoteScanReport {
        var results: [RemoteCommandResult] = []
        var raw: [String: ToolCommandOutput] = [:]
        for item in Self.scanCommands {
            let capture = ssh.runOutput(commandID: item.id, remoteCommand: item.command)
            results.append(capture.result)
            raw[item.id] = capture.output
        }

        let diskFilesystems = RemoteParsers.parseDF(raw["scan.df"]?.stdout ?? "")
        let inodeFilesystems = RemoteParsers.parseDF(raw["scan.inodes"]?.stdout ?? "")
        var findings: [RemoteStorageFinding] = []
        findings.append(contentsOf: pressureFindings(filesystems: diskFilesystems, bucket: "Disk pressure", privacy: privacy))
        findings.append(contentsOf: pressureFindings(filesystems: inodeFilesystems, bucket: "Inode pressure", privacy: privacy))
        findings.append(contentsOf: duFindings(output: raw["scan.du"], privacy: privacy))
        findings.append(contentsOf: largeFileFindings(output: raw["scan.large-files"]?.stdout ?? "", privacy: privacy))
        findings.append(contentsOf: journalFinding(output: raw["scan.journal"]?.stdout ?? "", privacy: privacy))
        findings.append(contentsOf: aptFindings(output: raw["scan.apt"]?.stdout ?? "", privacy: privacy))
        findings.append(contentsOf: dockerFindings(output: raw["scan.docker-df"]?.stdout ?? "", privacy: privacy))
        findings = deduplicate(findings)

        return RemoteScanReport(
            preset: preset,
            target: target,
            diskFilesystems: diskFilesystems,
            inodeFilesystems: inodeFilesystems,
            findings: findings,
            nativeGuidance: RemoteNativeGuidanceBuilder.guidance(for: findings),
            commands: results,
            coverage: RemoteScanCoverageBuilder.build(commands: results, osSummary: nil, target: target),
            nonClaims: RemoteScanReport.defaultNonClaims
        )
    }

    private func pressureFindings(filesystems: [RemoteFilesystemSummary], bucket: String, privacy: ReportPrivacyOptions) -> [RemoteStorageFinding] {
        filesystems.compactMap { filesystem in
            guard let capacity = filesystem.capacityPercent, capacity >= 90 else { return nil }
            return finding(
                path: filesystem.mount,
                displayPath: privacy.displayPath(filesystem.mount),
                bucket: bucket,
                bytes: filesystem.usedBytes,
                safety: .reviewRequired,
                action: .openGuidance,
                next: .reviewInFinder,
                evidence: "\(filesystem.filesystem) is at \(capacity)% on \(filesystem.mount)."
            )
        }
    }

    private func duFindings(output: ToolCommandOutput?, privacy: ReportPrivacyOptions) -> [RemoteStorageFinding] {
        var findings = RemoteParsers.parseDU(output?.stdout ?? "").map { row in
            classifyDURow(row, privacy: privacy)
        }
        for path in RemoteParsers.parsePermissionDeniedPaths(output?.stderr ?? "") {
            findings.append(
                finding(
                    path: path,
                    displayPath: privacy.displayPath(path),
                    bucket: "Permission denied",
                    bytes: nil,
                    safety: .reviewRequired,
                    action: .openGuidance,
                    next: .reviewInFinder,
                    evidence: "The remote account could not read this path during a report-only scan."
                )
            )
        }
        return findings
    }

    private func classifyDURow(_ row: RemoteDURow, privacy: ReportPrivacyOptions) -> RemoteStorageFinding {
        let path = row.path
        if path.contains("/var/lib/docker/volumes") {
            return finding(path: path, displayPath: privacy.displayPath(path), bucket: "Docker volumes", bytes: row.bytes, safety: .preserveByDefault, action: .nativeToolCommand, next: .protectByDefault, evidence: "Docker volumes can contain databases or app state.")
        }
        if path.contains("/var/lib/docker") {
            return finding(path: path, displayPath: privacy.displayPath(path), bucket: "Docker data", bytes: row.bytes, safety: .safeAfterCondition, action: .nativeToolCommand, next: .useNativeTool, evidence: "Docker-owned storage should be reviewed with Docker commands, not raw deletion.")
        }
        if path.contains("/releases/") {
            return finding(path: path, displayPath: privacy.displayPath(path), bucket: "Old deploy releases", bytes: row.bytes, safety: .reviewRequired, action: .openGuidance, next: .archiveCandidate, evidence: "Release directories can be stale, but may be needed for rollback.")
        }
        if path.hasPrefix("/tmp") || path.hasPrefix("/var/tmp") {
            return finding(path: path, displayPath: privacy.displayPath(path), bucket: "Remote temp", bytes: row.bytes, safety: .safeAfterCondition, action: .openGuidance, next: .reviewInFinder, evidence: "Temporary paths require age, owner, and active-process review before cleanup.")
        }
        if path.contains("/srv/") || path.contains("/var/lib/") {
            return finding(path: path, displayPath: privacy.displayPath(path), bucket: "App data", bytes: row.bytes, safety: .preserveByDefault, action: .reportOnly, next: .protectByDefault, evidence: "Application data paths can contain uploads, state, or databases.")
        }
        return finding(path: path, displayPath: privacy.displayPath(path), bucket: "Remote storage", bytes: row.bytes, safety: .reviewRequired, action: .openGuidance, next: .reviewInFinder, evidence: "Review this remote storage path before deciding whether it is disposable.")
    }

    private func largeFileFindings(output: String, privacy: ReportPrivacyOptions) -> [RemoteStorageFinding] {
        RemoteParsers.parseLargeFiles(output).map { row in
            let isBackup = row.path.localizedCaseInsensitiveContains("/backup")
                || row.path.localizedCaseInsensitiveContains("/backups/")
                || row.path.localizedCaseInsensitiveContains(".dump")
            return finding(
                path: row.path,
                displayPath: privacy.displayPath(row.path),
                bucket: isBackup ? "Large backup files" : "Large remote files",
                bytes: row.bytes,
                safety: isBackup ? .preserveByDefault : .reviewRequired,
                action: .openGuidance,
                next: isBackup ? .protectByDefault : .archiveCandidate,
                evidence: isBackup ? "Large backup-like files stay preserve-by-default." : "Large files are review signals, not cleanup permission."
            )
        }
    }

    private func journalFinding(output: String, privacy: ReportPrivacyOptions) -> [RemoteStorageFinding] {
        guard let bytes = RemoteParsers.parseJournalctlDiskUsage(output), bytes > 0 else { return [] }
        return [
            finding(
                path: "/var/log/journal",
                displayPath: privacy.displayPath("/var/log/journal"),
                bucket: "Journald logs",
                bytes: bytes,
                safety: .safeAfterCondition,
                action: .nativeToolCommand,
                next: .useNativeTool,
                evidence: "journalctl reported \(ByteFormat.string(bytes)) of journal usage; vacuum commands should be reviewed manually."
            )
        ]
    }

    private func aptFindings(output: String, privacy: ReportPrivacyOptions) -> [RemoteStorageFinding] {
        RemoteParsers.parseDU(output).map { row in
            finding(
                path: row.path,
                displayPath: privacy.displayPath(row.path),
                bucket: "APT cache",
                bytes: row.bytes,
                safety: .safeAfterCondition,
                action: .nativeToolCommand,
                next: .useNativeTool,
                evidence: "APT package archives should be cleaned with apt-get guidance, not raw deletion."
            )
        }
    }

    private func dockerFindings(output: String, privacy: ReportPrivacyOptions) -> [RemoteStorageFinding] {
        RemoteParsers.parseDockerSystemDF(output).compactMap { bucket in
            let bytes = bucket.reclaimableBytes ?? bucket.sizeBytes
            switch bucket.type {
            case "Images":
                return finding(path: "docker://images", displayPath: "docker://images", bucket: "Docker images", bytes: bytes, safety: .safeAfterCondition, action: .nativeToolCommand, next: .useNativeTool, evidence: "Docker image cleanup should use Docker's native review/prune flow.")
            case "Containers":
                return finding(path: "docker://containers", displayPath: "docker://containers", bucket: "Docker containers", bytes: bytes, safety: .safeAfterCondition, action: .nativeToolCommand, next: .useNativeTool, evidence: "Stopped containers may be removable only after service review.")
            case "Build Cache":
                return finding(path: "docker://build-cache", displayPath: "docker://build-cache", bucket: "Docker build cache", bytes: bytes, safety: .safeAfterCondition, action: .nativeToolCommand, next: .useNativeTool, evidence: "Docker build cache is best handled by Docker after review.")
            case "Local Volumes":
                return finding(path: "docker://volumes", displayPath: "docker://volumes", bucket: "Docker volumes", bytes: bucket.sizeBytes, safety: .preserveByDefault, action: .nativeToolCommand, next: .protectByDefault, evidence: "Docker volumes can contain databases or durable application state.")
            default:
                return nil
            }
        }
    }

    private func finding(
        path: String,
        displayPath: String,
        bucket: String,
        bytes: Int64?,
        safety: SafetyClass,
        action: ActionKind,
        next: ReviewNextAction,
        evidence: String
    ) -> RemoteStorageFinding {
        RemoteStorageFinding(
            remotePath: path,
            displayPath: displayPath,
            bucket: bucket,
            allocatedBytes: bytes,
            safetyClass: safety,
            actionKind: action,
            evidence: [Evidence(kind: "remote.\(bucket.lowercased().replacingOccurrences(of: " ", with: "-"))", message: evidence)],
            recommendedNextAction: next
        )
    }

    private func deduplicate(_ findings: [RemoteStorageFinding]) -> [RemoteStorageFinding] {
        var seen = Set<String>()
        return findings.filter { seen.insert($0.id).inserted }
    }
}

public enum RemoteNativeGuidanceBuilder {
    public static func guidance(for findings: [RemoteStorageFinding]) -> [RemoteNativeGuidance] {
        var guidance: [RemoteNativeGuidance] = []
        if findings.contains(where: { $0.bucket == "Journald logs" }) {
            guidance.append(RemoteNativeGuidance(id: "journald.vacuum.review", title: "Review journald retention", command: "journalctl --rotate && journalctl --vacuum-time=14d", risk: "manual-review", summary: "Vacuum archived journals only after confirming host logging requirements."))
        }
        if findings.contains(where: { $0.bucket == "APT cache" }) {
            guidance.append(RemoteNativeGuidance(id: "apt.cache.review", title: "Review APT package cache", command: "sudo apt-get autoclean && sudo apt-get clean", risk: "manual-review", summary: "Use apt-get cache commands manually; Ryddi does not run sudo cleanup remotely."))
        }
        if findings.contains(where: { $0.bucket.hasPrefix("Docker") }) {
            guidance.append(RemoteNativeGuidance(id: "docker.storage.review", title: "Review Docker storage", command: "docker system df -v", risk: "review-only", summary: "Inspect images, containers, build cache, and volumes before considering prune commands."))
        }
        if findings.contains(where: { $0.bucket == "Old deploy releases" }) {
            guidance.append(RemoteNativeGuidance(id: "deploy.releases.review", title: "Review old deploy releases", command: "ls -lah /opt /srv /var/www", risk: "manual-review", summary: "Keep rollback directories until the deploy process and rollback policy are understood."))
        }
        return guidance
    }
}

public enum RemoteReportBuilder {
    public static func build(report: RemoteScanReport, privacy: ReportPrivacyOptions = .default) -> RemoteMarkdownReport {
        var lines: [String] = []
        lines.append("# Ryddi Remote Target Report")
        lines.append("")
        lines.append("- Target: \(report.target.alias ?? report.target.input)")
        lines.append("- Host: \(report.target.resolvedHost ?? "unknown")")
        lines.append("- User: \(report.target.resolvedUser ?? "unknown")")
        lines.append("- Host key: \(report.target.knownHostsState)")
        lines.append("- Preset: \(report.preset.rawValue)")
        lines.append("- Path privacy: \(privacy.summary)")
        lines.append("")

        lines.append("## Coverage")
        lines.append("")
        lines.append("- Level: \(report.coverage.level.rawValue)")
        lines.append("- Explanation: \(MarkdownTable.cell(report.coverage.explanation))")
        lines.append("- Successful commands: \(report.coverage.successfulCommandIDs.count)")
        lines.append("- Failed commands: \(report.coverage.failedCommandIDs.count)")
        lines.append("- Timed out commands: \(report.coverage.timedOutCommandIDs.count)")
        lines.append("- Permission denied commands: \(report.coverage.permissionDeniedCommandIDs.count)")
        if !report.coverage.rows.isEmpty {
            lines.append("")
            lines.append("| Check | Status | Detail |")
            lines.append("| --- | --- | --- |")
            for row in report.coverage.rows {
                let values = [
                    row.label,
                    row.status.rawValue,
                    row.detail
                ].map(MarkdownTable.cell)
                lines.append("| \(values.joined(separator: " | ")) |")
            }
        }
        lines.append("")

        if !report.continuityWarnings.isEmpty {
            lines.append("## Target Continuity")
            lines.append("")
            lines.append("| Field | Previous | Current | Severity |")
            lines.append("| --- | --- | --- | --- |")
            for warning in report.continuityWarnings {
                let row = [
                    warning.field,
                    warning.previousValue,
                    warning.currentValue,
                    warning.severity
                ].map(MarkdownTable.cell)
                lines.append("| \(row.joined(separator: " | ")) |")
            }
            lines.append("")
        }

        lines.append("## Findings")
        if report.findings.isEmpty {
            if report.coverage.level == .unreachable {
                lines.append("No remote findings were produced because the target was unreachable or all evidence commands failed.")
            } else {
                lines.append("No remote findings were produced.")
            }
        } else {
            lines.append("| Bucket | Path | Size | Safety | Next Action |")
            lines.append("| --- | --- | ---: | --- | --- |")
            for finding in report.findings.sorted(by: { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }) {
                let displayPath = privacy.displayPath(finding.remotePath)
                let row = [
                    finding.bucket,
                    displayPath,
                    finding.allocatedBytes.map(ByteFormat.string) ?? "-",
                    finding.safetyClass.label,
                    finding.recommendedNextAction.label
                ].map(MarkdownTable.cell)
                lines.append("| \(row.joined(separator: " | ")) |")
            }
        }
        lines.append("")

        lines.append("## Native Guidance")
        if report.nativeGuidance.isEmpty {
            lines.append("- No native guidance generated.")
        } else {
            for item in report.nativeGuidance {
                lines.append("- \(item.title): `\(item.command)` - \(item.summary)")
            }
        }
        lines.append("")

        lines.append("## Manual Command Cards")
        if report.commandCards.isEmpty {
            lines.append("- No manual command cards generated.")
        } else {
            lines.append("| Title | Kind | Risk | Command | Why |")
            lines.append("| --- | --- | --- | --- | --- |")
            for card in report.commandCards {
                let row = [
                    card.title,
                    card.kind.label,
                    card.risk.label,
                    card.displayCommand,
                    card.explanation
                ].map(MarkdownTable.cell)
                lines.append("| \(row.joined(separator: " | ")) |")
            }
        }
        lines.append("")

        lines.append("## Command Receipts")
        for command in report.commands {
            lines.append("- \(command.commandID): \(command.exitCode.map(String.init) ?? "blocked") `\(command.displayCommand)`")
        }
        lines.append("")

        lines.append("## Non-Claims")
        for claim in report.nonClaims {
            lines.append("- \(claim)")
        }
        return RemoteMarkdownReport(markdown: lines.joined(separator: "\n"))
    }
}
