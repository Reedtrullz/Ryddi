import Foundation

public struct EvidenceReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let title: String
    public let markdown: String
    public let findingCount: Int
    public let expectedAutoSafeBytes: Int64
    public let reviewBytes: Int64
    public let protectedBytes: Int64
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        title: String,
        markdown: String,
        findingCount: Int,
        expectedAutoSafeBytes: Int64,
        reviewBytes: Int64,
        protectedBytes: Int64,
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.markdown = markdown
        self.findingCount = findingCount
        self.expectedAutoSafeBytes = expectedAutoSafeBytes
        self.reviewBytes = reviewBytes
        self.protectedBytes = protectedBytes
        self.nonClaims = nonClaims
    }
}

public enum EvidenceReportBuilder {
    public static func build(
        title: String = "Ryddi Evidence Report",
        overview: ScanOverview,
        findings: [Finding],
        scopes: [ScanScope],
        diskStatus: DiskStatusSnapshot? = nil,
        userPathPolicy: UserPathPolicy = .empty,
        topLimit: Int = 25,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> EvidenceReport {
        let id = UUID().uuidString
        var nonClaims = [
            "No cleanup was executed by this report.",
            "Reclaim estimates use scan-time allocated bytes and are not a promise of exact Finder or df free-space gains.",
            "Missing or denied scopes can make this report incomplete until macOS permissions are granted.",
            "Protected and excluded user policy is local-only and may contain paths or reasons entered on this Mac.",
            "VM, container, browser profile, credential, creative asset, and unknown app-state data require review or native tools rather than raw deletion."
        ]
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local audit data may still contain full original paths.")
        }
        let markdown = markdown(
            id: id,
            title: title,
            createdAt: now,
            overview: overview,
            findings: findings,
            scopes: scopes,
            diskStatus: diskStatus,
            userPathPolicy: userPathPolicy,
            topLimit: topLimit,
            privacy: privacy,
            nonClaims: nonClaims
        )
        return EvidenceReport(
            id: id,
            createdAt: now,
            title: title,
            markdown: markdown,
            findingCount: overview.findingCount,
            expectedAutoSafeBytes: overview.expectedAutoSafeBytes,
            reviewBytes: overview.reviewBytes,
            protectedBytes: overview.protectedBytes,
            nonClaims: nonClaims
        )
    }

    private static func markdown(
        id: String,
        title: String,
        createdAt: Date,
        overview: ScanOverview,
        findings: [Finding],
        scopes: [ScanScope],
        diskStatus: DiskStatusSnapshot?,
        userPathPolicy: UserPathPolicy,
        topLimit: Int,
        privacy: ReportPrivacyOptions,
        nonClaims: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append("- Report id: `\(id)`")
        lines.append("- Generated: \(isoString(createdAt))")
        lines.append("- Scan generated: \(isoString(overview.generatedAt))")
        lines.append("")

        lines.append("## Summary")
        lines.append(table(
            headers: ["Metric", "Value"],
            rows: [
                ["Requested scopes", "\(scopes.count)"],
                ["Findings", "\(overview.findingCount)"],
                ["Allocated scanned", ByteFormat.string(overview.totalAllocatedSize)],
                ["Logical scanned", ByteFormat.string(overview.totalLogicalSize)],
                ["Auto-safe bytes", ByteFormat.string(overview.expectedAutoSafeBytes)],
                ["Review bytes", ByteFormat.string(overview.reviewBytes)],
                ["Protected bytes", ByteFormat.string(overview.protectedBytes)]
            ]
        ))
        lines.append("")

        if let diskStatus {
            lines.append("## Disk Status")
            var rows = [
                ["Path", privacy.displayPath(diskStatus.path)],
                ["Pressure", diskStatus.pressure.label],
                ["Free", diskStatus.statusLine]
            ]
            if let volumeName = diskStatus.volumeName {
                rows.append(["Volume", volumeName])
            }
            if let totalBytes = diskStatus.totalBytes {
                rows.append(["Total", ByteFormat.string(totalBytes)])
            }
            lines.append(table(headers: ["Metric", "Value"], rows: rows))
            lines.append("")
        }

        lines.append("## Scan Coverage")
        if overview.scopeSummaries.isEmpty {
            lines.append("No scope coverage data was recorded.")
        } else {
            lines.append(table(
                headers: ["State", "Scope", "Path", "Note"],
                rows: overview.scopeSummaries.map {
                    [$0.permissionState.rawValue, $0.name, privacy.displayPath($0.path), privacy.displayText($0.message, knownPaths: [$0.path])]
                }
            ))
        }
        lines.append("")

        lines.append("## Safety Buckets")
        lines.append(summaryTable(overview.safetySummaries))
        lines.append("")

        lines.append("## Top Categories")
        lines.append(summaryTable(Array(overview.categorySummaries.prefix(12))))
        lines.append("")

        lines.append("## Top Owners")
        if overview.ownerSummaries.isEmpty {
            lines.append("No owner summaries were recorded.")
        } else {
            lines.append(table(
                headers: ["Owner", "Allocated", "Items", "Dominant Category", "Auto-safe", "Review", "Protected"],
                rows: overview.ownerSummaries.prefix(12).map {
                    [
                        $0.ownerName,
                        ByteFormat.string($0.allocatedSize),
                        "\($0.count)",
                        $0.dominantCategory,
                        ByteFormat.string($0.expectedAutoSafeBytes),
                        ByteFormat.string($0.reviewBytes),
                        ByteFormat.string($0.protectedBytes)
                    ]
                }
            ))
        }
        lines.append("")

        lines.append("## Top Findings")
        let topFindings = Array(overview.topFindings.prefix(topLimit))
        if topFindings.isEmpty {
            lines.append("No findings matched the current scan settings.")
        } else {
            lines.append(table(
                headers: ["Allocated", "Safety", "Category", "Action", "Path"],
                rows: topFindings.map {
                    [
                        ByteFormat.string($0.allocatedSize),
                        $0.safetyClass.label,
                        $0.primaryCategory,
                        $0.actionKind.label,
                        privacy.displayPath($0.path)
                    ]
                }
            ))
        }
        lines.append("")

        lines.append("## User Protections And Exclusions")
        if userPathPolicy.rules.isEmpty {
            lines.append("No user path policy rules were configured for this report.")
        } else {
            lines.append(table(
                headers: ["Policy", "Path", "Reason", "Descendants"],
                rows: userPathPolicy.rules.map {
                    [$0.kind.label, privacy.displayPath($0.path), privacy.displayUserText($0.reason), $0.includeDescendants ? "yes" : "no"]
                }
            ))
        }
        lines.append("")

        lines.append("## Evidence Notes")
        let evidenceCounts = Dictionary(grouping: findings.flatMap(\.evidence), by: \.kind)
            .map { key, values in (key, values.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 > rhs.1
            }
        if evidenceCounts.isEmpty {
            lines.append("No additional evidence notes were attached.")
        } else {
            lines.append(table(
                headers: ["Evidence kind", "Count"],
                rows: evidenceCounts.map { [$0.0, "\($0.1)"] }
            ))
        }
        lines.append("")

        lines.append("## Accounting Notes")
        for note in overview.accountingNotes + (diskStatus?.notes ?? []) {
            lines.append("- \(note)")
        }
        lines.append("")

        lines.append("## Explicit Non-Claims")
        for nonClaim in nonClaims {
            lines.append("- \(nonClaim)")
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func summaryTable(_ summaries: [BucketSummary]) -> String {
        if summaries.isEmpty {
            return "No bucket data was recorded."
        }
        return table(
            headers: ["Name", "Allocated", "Logical", "Items"],
            rows: summaries.map {
                [$0.name, ByteFormat.string($0.allocatedSize), ByteFormat.string($0.logicalSize), "\($0.count)"]
            }
        )
    }

    private static func table(headers: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append("| \(headers.map(markdownCell).joined(separator: " | ")) |")
        lines.append("| \(headers.map { _ in "---" }.joined(separator: " | ")) |")
        for row in rows {
            lines.append("| \(row.map(markdownCell).joined(separator: " | ")) |")
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownCell(_ value: String) -> String {
        let compact = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "-" : compact
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public final class ReportStore: @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(root: URL = ReportStore.defaultRoot(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_REPORT_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ryddi/Reports", isDirectory: true)
    }

    @discardableResult
    public func save(report: EvidenceReport) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("report-\(report.id).md")
        try report.markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    public func save(executionReceiptReport report: ExecutionReceiptReport) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("receipt-report-\(report.receiptID)-\(report.id).md")
        try report.markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    public func save(planReport report: ReclaimPlanReport) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("plan-report-\(report.planID)-\(report.id).md")
        try report.markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    public func save(growthReport report: GrowthReport) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("growth-report-\(report.currentSnapshotID)-\(report.id).md")
        try report.markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    public func save(userPathPolicyDocument document: UserPathPolicyDocument) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("user-path-policy-\(document.id).json")
        try encoder.encode(document).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    public func save(userRulePackDocument document: UserRulePackDocument) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("user-rules-\(document.id).json")
        try encoder.encode(document).write(to: url, options: .atomic)
        return url
    }
}
