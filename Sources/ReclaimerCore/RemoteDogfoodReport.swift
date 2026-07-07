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
        let shouldSanitize = privacy.pathStyle != .full || privacy.redactUserText
        let totalFindingBytes = scan.findings.reduce(into: Int64(0)) { partialResult, finding in
            partialResult += finding.allocatedBytes ?? 0
        }
        let reviewQueueCounts = Dictionary(grouping: scan.findings, by: { $0.recommendedNextAction.rawValue })
            .mapValues(\.count)
        let commandResults = (probe?.commands ?? []) + scan.commands
        let reportTarget = shouldSanitize ? sanitizedTarget(from: scan.target) : scan.target
        let reportCommandResults = shouldSanitize ? commandResults.map(sanitizedCommandResult) : commandResults
        let id = UUID().uuidString
        let baseNonClaims = [
            "No cleanup was executed on the remote target.",
            "Remote dogfood is read-only and uses bounded probe, scan, and growth evidence.",
            "This report does not prove current server state after the scan time.",
            "This report does not prove exact reclaimable bytes or cleanup safety.",
            "Ryddi did not store SSH private keys, passwords, passphrases, sudo passwords, tokens, or remote secrets."
        ]
        var nonClaims = baseNonClaims
        nonClaims.append(contentsOf: probe?.nonClaims ?? [])
        nonClaims.append(contentsOf: scan.nonClaims)
        nonClaims.append(contentsOf: growth?.nonClaims ?? [])
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local audit JSON may still contain original remote paths.")
        }
        let dedupedNonClaims = unique(nonClaims)

        let report = RemoteDogfoodReport(
            id: id,
            createdAt: now,
            target: reportTarget,
            probeID: probe?.id,
            scanID: scan.id,
            growthReportID: growth?.id,
            osSummary: probe?.osSummary,
            diskPressureSummary: diskPressureSummary(scan.diskFilesystems),
            findingCount: scan.findings.count,
            totalFindingBytes: totalFindingBytes,
            reviewQueueCounts: reviewQueueCounts,
            commandResults: reportCommandResults,
            nonClaims: dedupedNonClaims,
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

    private static func markdown(
        for report: RemoteDogfoodReport,
        scan: RemoteScanReport,
        growth: RemoteGrowthReport?,
        privacy: ReportPrivacyOptions
    ) -> String {
        let targetLabel = report.target.alias ?? report.target.input
        let hostLabel = report.target.resolvedHost ?? "unknown"

        var lines: [String] = []
        lines.append("# Ryddi Remote Dogfood Report")
        lines.append("")
        lines.append("- Report id: `\(report.id)`")
        lines.append("- Generated: \(isoString(report.createdAt))")
        lines.append("- Target: \(targetLabel)")
        lines.append("- Host: \(hostLabel)")
        lines.append("- Probe: \(report.probeID ?? "none")")
        lines.append("- Scan: \(report.scanID)")
        lines.append("- Growth report: \(report.growthReportID ?? "none")")
        lines.append("- OS: \(report.osSummary ?? "unknown")")
        lines.append("- Disk pressure: \(report.diskPressureSummary)")
        lines.append("- Findings: \(report.findingCount)")
        lines.append("- Finding bytes: \(ByteFormat.string(report.totalFindingBytes))")
        lines.append("")

        lines.append("## Largest Findings")
        if scan.findings.isEmpty {
            lines.append("No remote findings were produced.")
        } else {
            for finding in scan.findings
                .sorted(by: { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) })
                .prefix(10) {
                lines.append("- \(ByteFormat.string(finding.allocatedBytes ?? 0)) \(finding.bucket): `\(privacy.displayPath(finding.remotePath))`")
            }
        }

        if let growth {
            lines.append("")
            lines.append("## Saved Growth Signal")
            lines.append("- Compared scans: `\(growth.previousScanID)` -> `\(growth.currentScanID)`")
            lines.append("- Delta: \(signedBytes(growth.deltaAllocatedBytes))")
        }

        lines.append("")
        lines.append("## Review Queue Counts")
        if report.reviewQueueCounts.isEmpty {
            lines.append("No review queues were produced.")
        } else {
            for key in report.reviewQueueCounts.keys.sorted() {
                lines.append("- \(key): \(report.reviewQueueCounts[key] ?? 0)")
            }
        }

        lines.append("")
        lines.append("## Command Receipts")
        if report.commandResults.isEmpty {
            lines.append("No command receipts were captured.")
        } else {
            for command in report.commandResults.prefix(20) {
                lines.append("- `\(command.commandID)`: exit \(command.exitCode.map(String.init) ?? "unknown"), timedOut=\(command.timedOut)")
            }
        }

        lines.append("")
        lines.append("## Explicit Non-Claims")
        for note in report.nonClaims {
            lines.append("- \(note)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func sanitizedTarget(from _: RemoteTargetReference) -> RemoteTargetReference {
        RemoteTargetReference(
            input: "<target redacted>",
            alias: nil,
            resolvedUser: nil,
            resolvedHost: "<host redacted>",
            resolvedPort: nil,
            knownHostsState: "redacted",
            fingerprint: nil
        )
    }

    private static func sanitizedCommandResult(from result: RemoteCommandResult) -> RemoteCommandResult {
        RemoteCommandResult(
            commandID: result.commandID,
            displayCommand: "<command redacted>",
            exitCode: result.exitCode,
            timedOut: result.timedOut,
            stdoutPreview: [],
            stderrPreview: [],
            redactionApplied: true
        )
    }

    private static func diskPressureSummary(_ filesystems: [RemoteFilesystemSummary]) -> String {
        guard let worst = filesystems.max(by: {
            ($0.capacityPercent ?? -1) < ($1.capacityPercent ?? -1)
        }) else {
            return "Unknown"
        }
        guard let capacity = worst.capacityPercent else {
            return "Unknown"
        }
        return "\(capacity)% on \(worst.mount)"
    }

    private static func signedBytes(_ bytes: Int64) -> String {
        if bytes > 0 {
            return "+\(ByteFormat.string(bytes))"
        }
        return ByteFormat.string(bytes)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
