import Foundation

public struct RemoteBucketGrowthDelta: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bucket }
    public let bucket: String
    public let previousAllocatedBytes: Int64
    public let currentAllocatedBytes: Int64
    public let deltaAllocatedBytes: Int64
    public let previousCount: Int
    public let currentCount: Int

    public init(
        bucket: String,
        previousAllocatedBytes: Int64,
        currentAllocatedBytes: Int64,
        deltaAllocatedBytes: Int64,
        previousCount: Int,
        currentCount: Int
    ) {
        self.bucket = bucket
        self.previousAllocatedBytes = previousAllocatedBytes
        self.currentAllocatedBytes = currentAllocatedBytes
        self.deltaAllocatedBytes = deltaAllocatedBytes
        self.previousCount = previousCount
        self.currentCount = currentCount
    }
}

public struct RemoteFindingGrowthDelta: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(bucket):\(remotePath)" }
    public let remotePath: String
    public let displayPath: String
    public let bucket: String
    public let previousAllocatedBytes: Int64
    public let currentAllocatedBytes: Int64
    public let deltaAllocatedBytes: Int64
    public let currentSafetyClass: SafetyClass?
    public let recommendedNextAction: ReviewNextAction?

    public init(
        remotePath: String,
        displayPath: String,
        bucket: String,
        previousAllocatedBytes: Int64,
        currentAllocatedBytes: Int64,
        deltaAllocatedBytes: Int64,
        currentSafetyClass: SafetyClass?,
        recommendedNextAction: ReviewNextAction?
    ) {
        self.remotePath = remotePath
        self.displayPath = displayPath
        self.bucket = bucket
        self.previousAllocatedBytes = previousAllocatedBytes
        self.currentAllocatedBytes = currentAllocatedBytes
        self.deltaAllocatedBytes = deltaAllocatedBytes
        self.currentSafetyClass = currentSafetyClass
        self.recommendedNextAction = recommendedNextAction
    }
}

public struct RemoteGrowthReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let target: RemoteTargetReference
    public let previousScanID: String
    public let currentScanID: String
    public let previousCreatedAt: Date
    public let currentCreatedAt: Date
    public let previousAllocatedBytes: Int64
    public let currentAllocatedBytes: Int64
    public let deltaAllocatedBytes: Int64
    public let previousFindingCount: Int
    public let currentFindingCount: Int
    public let bucketDeltas: [RemoteBucketGrowthDelta]
    public let findingDeltas: [RemoteFindingGrowthDelta]
    public let nonClaims: [String]
    public let markdown: String

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        target: RemoteTargetReference,
        previousScanID: String,
        currentScanID: String,
        previousCreatedAt: Date,
        currentCreatedAt: Date,
        previousAllocatedBytes: Int64,
        currentAllocatedBytes: Int64,
        deltaAllocatedBytes: Int64,
        previousFindingCount: Int,
        currentFindingCount: Int,
        bucketDeltas: [RemoteBucketGrowthDelta],
        findingDeltas: [RemoteFindingGrowthDelta],
        nonClaims: [String],
        markdown: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.target = target
        self.previousScanID = previousScanID
        self.currentScanID = currentScanID
        self.previousCreatedAt = previousCreatedAt
        self.currentCreatedAt = currentCreatedAt
        self.previousAllocatedBytes = previousAllocatedBytes
        self.currentAllocatedBytes = currentAllocatedBytes
        self.deltaAllocatedBytes = deltaAllocatedBytes
        self.previousFindingCount = previousFindingCount
        self.currentFindingCount = currentFindingCount
        self.bucketDeltas = bucketDeltas
        self.findingDeltas = findingDeltas
        self.nonClaims = nonClaims
        self.markdown = markdown
    }
}

public enum RemoteGrowthReportBuilder {
    public static func build(
        previous: RemoteScanReport,
        current: RemoteScanReport,
        limit: Int = 25,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> RemoteGrowthReport {
        let target = current.target
        let previousTotal = totalAllocatedBytes(previous.findings)
        let currentTotal = totalAllocatedBytes(current.findings)
        let bucketDeltas = Array(bucketDeltas(previous: previous.findings, current: current.findings).prefix(limit))
        let findingDeltas = Array(findingDeltas(previous: previous.findings, current: current.findings, privacy: privacy).prefix(limit))
        var nonClaims = [
            "No cleanup was executed on the remote target.",
            "This report compares saved remote scan reports; it does not prove exact current server state.",
            "Remote growth deltas use scan-time command output and can differ from df, filesystem snapshots, hard links, sparse files, Docker accounting, and native-tool estimates.",
            "Permission, sudo, SSH identity, scan preset, and command availability changes between scans can make deltas incomplete or not directly comparable.",
            "A positive remote growth delta is a review signal, not proof that a path is trash or safe to remove."
        ]
        let continuityWarnings = RemoteTargetContinuity.warnings(previous: previous.target, current: current.target)
        if !continuityWarnings.isEmpty {
            let fields = continuityWarnings.map(\.field).joined(separator: ", ")
            nonClaims.append("The compared remote target identities differ (\(fields)); review target metadata before treating deltas as the same host.")
        } else if previous.target.id != current.target.id || previous.target.resolvedHost != current.target.resolvedHost {
            nonClaims.append("The compared remote target labels differ; review target metadata before treating deltas as the same host.")
        }
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local remote scan JSON may still contain full original paths.")
        }

        let report = RemoteGrowthReport(
            createdAt: now,
            target: target,
            previousScanID: previous.id,
            currentScanID: current.id,
            previousCreatedAt: previous.createdAt,
            currentCreatedAt: current.createdAt,
            previousAllocatedBytes: previousTotal,
            currentAllocatedBytes: currentTotal,
            deltaAllocatedBytes: currentTotal - previousTotal,
            previousFindingCount: previous.findings.count,
            currentFindingCount: current.findings.count,
            bucketDeltas: bucketDeltas,
            findingDeltas: findingDeltas,
            nonClaims: nonClaims,
            markdown: ""
        )
        return RemoteGrowthReport(
            id: report.id,
            createdAt: report.createdAt,
            target: report.target,
            previousScanID: report.previousScanID,
            currentScanID: report.currentScanID,
            previousCreatedAt: report.previousCreatedAt,
            currentCreatedAt: report.currentCreatedAt,
            previousAllocatedBytes: report.previousAllocatedBytes,
            currentAllocatedBytes: report.currentAllocatedBytes,
            deltaAllocatedBytes: report.deltaAllocatedBytes,
            previousFindingCount: report.previousFindingCount,
            currentFindingCount: report.currentFindingCount,
            bucketDeltas: report.bucketDeltas,
            findingDeltas: report.findingDeltas,
            nonClaims: report.nonClaims,
            markdown: markdown(for: report)
        )
    }

    private static func bucketDeltas(previous: [RemoteStorageFinding], current: [RemoteStorageFinding]) -> [RemoteBucketGrowthDelta] {
        let previousBuckets = groupedByBucket(previous)
        let currentBuckets = groupedByBucket(current)
        return Set(previousBuckets.keys).union(currentBuckets.keys)
            .map { bucket in
                let previousRows = previousBuckets[bucket] ?? []
                let currentRows = currentBuckets[bucket] ?? []
                let previousBytes = totalAllocatedBytes(previousRows)
                let currentBytes = totalAllocatedBytes(currentRows)
                return RemoteBucketGrowthDelta(
                    bucket: bucket,
                    previousAllocatedBytes: previousBytes,
                    currentAllocatedBytes: currentBytes,
                    deltaAllocatedBytes: currentBytes - previousBytes,
                    previousCount: previousRows.count,
                    currentCount: currentRows.count
                )
            }
            .sorted {
                let lhsMagnitude = abs($0.deltaAllocatedBytes)
                let rhsMagnitude = abs($1.deltaAllocatedBytes)
                if lhsMagnitude == rhsMagnitude {
                    return $0.bucket < $1.bucket
                }
                return lhsMagnitude > rhsMagnitude
            }
    }

    private static func findingDeltas(
        previous: [RemoteStorageFinding],
        current: [RemoteStorageFinding],
        privacy: ReportPrivacyOptions
    ) -> [RemoteFindingGrowthDelta] {
        let previousRows = Dictionary(grouping: previous, by: findingKey).compactMapValues(\.first)
        let currentRows = Dictionary(grouping: current, by: findingKey).compactMapValues(\.first)
        return Set(previousRows.keys).union(currentRows.keys)
            .compactMap { key in
                guard let row = currentRows[key] ?? previousRows[key] else { return nil }
                let previousBytes = previousRows[key]?.allocatedBytes ?? 0
                let currentBytes = currentRows[key]?.allocatedBytes ?? 0
                return RemoteFindingGrowthDelta(
                    remotePath: row.remotePath,
                    displayPath: privacy.displayPath(row.remotePath),
                    bucket: row.bucket,
                    previousAllocatedBytes: previousBytes,
                    currentAllocatedBytes: currentBytes,
                    deltaAllocatedBytes: currentBytes - previousBytes,
                    currentSafetyClass: currentRows[key]?.safetyClass,
                    recommendedNextAction: currentRows[key]?.recommendedNextAction
                )
            }
            .sorted {
                let lhsMagnitude = abs($0.deltaAllocatedBytes)
                let rhsMagnitude = abs($1.deltaAllocatedBytes)
                if lhsMagnitude == rhsMagnitude {
                    return $0.remotePath < $1.remotePath
                }
                return lhsMagnitude > rhsMagnitude
            }
    }

    private static func markdown(for report: RemoteGrowthReport) -> String {
        var lines: [String] = []
        lines.append("# Ryddi Remote Growth Report")
        lines.append("")
        lines.append("- Report id: `\(report.id)`")
        lines.append("- Generated: \(isoString(report.createdAt))")
        lines.append("- Target: \(report.target.alias ?? report.target.input)")
        lines.append("- Host: \(report.target.resolvedHost ?? "unknown")")
        lines.append("- User: \(report.target.resolvedUser ?? "unknown")")
        lines.append("")

        lines.append("## Summary")
        lines.append(table(
            headers: ["Metric", "Previous", "Current", "Delta"],
            rows: [
                ["Remote scan", "`\(report.previousScanID)`", "`\(report.currentScanID)`", "-"],
                ["Created", isoString(report.previousCreatedAt), isoString(report.currentCreatedAt), "-"],
                ["Allocated findings", ByteFormat.string(report.previousAllocatedBytes), ByteFormat.string(report.currentAllocatedBytes), signedBytes(report.deltaAllocatedBytes)],
                ["Findings", "\(report.previousFindingCount)", "\(report.currentFindingCount)", signedInt(report.currentFindingCount - report.previousFindingCount)]
            ]
        ))
        lines.append("")

        lines.append("## Largest Bucket Deltas")
        if report.bucketDeltas.isEmpty {
            lines.append("No remote bucket deltas were recorded.")
        } else {
            lines.append(table(
                headers: ["Delta", "Current", "Previous", "Current Items", "Previous Items", "Bucket"],
                rows: report.bucketDeltas.map {
                    [
                        signedBytes($0.deltaAllocatedBytes),
                        ByteFormat.string($0.currentAllocatedBytes),
                        ByteFormat.string($0.previousAllocatedBytes),
                        "\($0.currentCount)",
                        "\($0.previousCount)",
                        $0.bucket
                    ]
                }
            ))
        }
        lines.append("")

        lines.append("## Largest Path Deltas")
        if report.findingDeltas.isEmpty {
            lines.append("No remote path deltas were recorded.")
        } else {
            lines.append(table(
                headers: ["Delta", "Current", "Previous", "Safety", "Next Action", "Path"],
                rows: report.findingDeltas.map {
                    [
                        signedBytes($0.deltaAllocatedBytes),
                        ByteFormat.string($0.currentAllocatedBytes),
                        ByteFormat.string($0.previousAllocatedBytes),
                        $0.currentSafetyClass?.label ?? "-",
                        $0.recommendedNextAction?.label ?? "-",
                        $0.displayPath
                    ]
                }
            ))
        }
        lines.append("")

        lines.append("## Explicit Non-Claims")
        for note in report.nonClaims {
            lines.append("- \(note)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func groupedByBucket(_ findings: [RemoteStorageFinding]) -> [String: [RemoteStorageFinding]] {
        Dictionary(grouping: findings, by: \.bucket)
    }

    private static func findingKey(_ finding: RemoteStorageFinding) -> String {
        "\(finding.bucket):\(finding.remotePath)"
    }

    private static func totalAllocatedBytes(_ findings: [RemoteStorageFinding]) -> Int64 {
        findings.reduce(Int64(0)) { $0 + ($1.allocatedBytes ?? 0) }
    }

    private static func signedBytes(_ bytes: Int64) -> String {
        bytes > 0 ? "+\(ByteFormat.string(bytes))" : ByteFormat.string(bytes)
    }

    private static func signedInt(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private static func table(headers: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append("| \(headers.map(MarkdownTable.cell).joined(separator: " | ")) |")
        lines.append("| \(headers.map { _ in "---" }.joined(separator: " | ")) |")
        for row in rows {
            lines.append("| \(row.map(MarkdownTable.cell).joined(separator: " | ")) |")
        }
        return lines.joined(separator: "\n")
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
