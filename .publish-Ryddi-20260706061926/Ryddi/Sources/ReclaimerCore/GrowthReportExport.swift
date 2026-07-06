import Foundation

public struct GrowthReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let title: String
    public let group: GrowthGroup
    public let previousSnapshotID: String
    public let currentSnapshotID: String
    public let previousCreatedAt: Date
    public let currentCreatedAt: Date
    public let deltaAllocatedSize: Int64
    public let deltaLogicalSize: Int64
    public let deltaFindingCount: Int
    public let deltas: [BucketGrowthDelta]
    public let nonClaims: [String]
    public let markdown: String

    public init(
        id: String,
        createdAt: Date,
        title: String,
        group: GrowthGroup,
        previousSnapshotID: String,
        currentSnapshotID: String,
        previousCreatedAt: Date,
        currentCreatedAt: Date,
        deltaAllocatedSize: Int64,
        deltaLogicalSize: Int64,
        deltaFindingCount: Int,
        deltas: [BucketGrowthDelta],
        nonClaims: [String],
        markdown: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.group = group
        self.previousSnapshotID = previousSnapshotID
        self.currentSnapshotID = currentSnapshotID
        self.previousCreatedAt = previousCreatedAt
        self.currentCreatedAt = currentCreatedAt
        self.deltaAllocatedSize = deltaAllocatedSize
        self.deltaLogicalSize = deltaLogicalSize
        self.deltaFindingCount = deltaFindingCount
        self.deltas = deltas
        self.nonClaims = nonClaims
        self.markdown = markdown
    }
}

public enum GrowthReportBuilder {
    public static func build(
        title: String = "Ryddi Growth Report",
        previous: ScanSnapshot,
        current: ScanSnapshot,
        group: GrowthGroup = .category,
        limit: Int = 25,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> GrowthReport {
        let id = UUID().uuidString
        var nonClaims = [
            "No cleanup was executed by this report.",
            "This report compares saved scan snapshots; it does not prove exact current disk state.",
            "Growth deltas use scan-time allocated bytes and can differ from Finder, df, APFS purgeable storage, snapshots, clones, and hard links.",
            "Permission, scope, and rule changes between scans can make deltas incomplete or not directly comparable.",
            "A positive growth delta is a review signal, not proof that a path is trash or safe to remove."
        ]
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local snapshot JSON may still contain full original paths.")
        }
        let deltas = Array(FindingAnalytics.growthDeltas(previous: previous, current: current, group: group).prefix(limit))
        let report = GrowthReport(
            id: id,
            createdAt: now,
            title: title,
            group: group,
            previousSnapshotID: previous.id,
            currentSnapshotID: current.id,
            previousCreatedAt: previous.createdAt,
            currentCreatedAt: current.createdAt,
            deltaAllocatedSize: current.totalAllocatedSize - previous.totalAllocatedSize,
            deltaLogicalSize: current.totalLogicalSize - previous.totalLogicalSize,
            deltaFindingCount: current.findingCount - previous.findingCount,
            deltas: deltas,
            nonClaims: nonClaims,
            markdown: ""
        )
        return GrowthReport(
            id: report.id,
            createdAt: report.createdAt,
            title: report.title,
            group: report.group,
            previousSnapshotID: report.previousSnapshotID,
            currentSnapshotID: report.currentSnapshotID,
            previousCreatedAt: report.previousCreatedAt,
            currentCreatedAt: report.currentCreatedAt,
            deltaAllocatedSize: report.deltaAllocatedSize,
            deltaLogicalSize: report.deltaLogicalSize,
            deltaFindingCount: report.deltaFindingCount,
            deltas: report.deltas,
            nonClaims: report.nonClaims,
            markdown: markdown(for: report, previous: previous, current: current, privacy: privacy)
        )
    }

    private static func markdown(
        for report: GrowthReport,
        previous: ScanSnapshot,
        current: ScanSnapshot,
        privacy: ReportPrivacyOptions
    ) -> String {
        var lines: [String] = []
        lines.append("# \(report.title)")
        lines.append("")
        lines.append("- Report id: `\(report.id)`")
        lines.append("- Generated: \(isoString(report.createdAt))")
        lines.append("- Group: \(report.group.label)")
        lines.append("")

        lines.append("## Summary")
        lines.append(table(
            headers: ["Metric", "Previous", "Current", "Delta"],
            rows: [
                ["Snapshot", "`\(previous.id)`", "`\(current.id)`", "-"],
                ["Created", isoString(previous.createdAt), isoString(current.createdAt), "-"],
                ["Allocated scanned", ByteFormat.string(previous.totalAllocatedSize), ByteFormat.string(current.totalAllocatedSize), signedBytes(report.deltaAllocatedSize)],
                ["Logical scanned", ByteFormat.string(previous.totalLogicalSize), ByteFormat.string(current.totalLogicalSize), signedBytes(report.deltaLogicalSize)],
                ["Findings", "\(previous.findingCount)", "\(current.findingCount)", signedInt(report.deltaFindingCount)],
                ["Auto-safe bytes", ByteFormat.string(previous.expectedAutoSafeBytes), ByteFormat.string(current.expectedAutoSafeBytes), signedBytes(current.expectedAutoSafeBytes - previous.expectedAutoSafeBytes)],
                ["Review bytes", ByteFormat.string(previous.reviewBytes), ByteFormat.string(current.reviewBytes), signedBytes(current.reviewBytes - previous.reviewBytes)],
                ["Protected bytes", ByteFormat.string(previous.protectedBytes), ByteFormat.string(current.protectedBytes), signedBytes(current.protectedBytes - previous.protectedBytes)]
            ]
        ))
        lines.append("")

        lines.append("## Largest \(report.group.label) Deltas")
        if report.deltas.isEmpty {
            lines.append("No bucket deltas were recorded for this group.")
        } else {
            lines.append(table(
                headers: ["Delta", "Current", "Previous", "Current Items", "Previous Items", report.group.label],
                rows: report.deltas.map {
                    [
                        signedBytes($0.deltaAllocatedSize),
                        ByteFormat.string($0.currentAllocatedSize),
                        ByteFormat.string($0.previousAllocatedSize),
                        "\($0.currentCount)",
                        "\($0.previousCount)",
                        $0.name
                    ]
                }
            ))
        }
        lines.append("")

        lines.append("## Scan Coverage")
        lines.append(coverageTable(previous: previous, current: current, privacy: privacy))
        lines.append("")

        lines.append("## Current Top Finding Paths")
        if current.topFindingPaths.isEmpty {
            lines.append("No top finding paths were recorded in the current snapshot.")
        } else {
            lines.append(table(
                headers: ["Path"],
                rows: current.topFindingPaths.prefix(20).map { [privacy.displayPath($0)] }
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

    private static func coverageTable(previous: ScanSnapshot, current: ScanSnapshot, privacy: ReportPrivacyOptions) -> String {
        let names = Set(previous.scopeSummaries.map(\.name)).union(current.scopeSummaries.map(\.name)).sorted()
        guard !names.isEmpty else {
            return "No scope coverage was recorded in these snapshots."
        }
        let previousByName = Dictionary(grouping: previous.scopeSummaries, by: \.name).compactMapValues(\.first)
        let currentByName = Dictionary(grouping: current.scopeSummaries, by: \.name).compactMapValues(\.first)
        return table(
            headers: ["Scope", "Previous", "Current", "Current Path"],
            rows: names.map { name in
                let previousState = previousByName[name]?.permissionState.rawValue ?? "-"
                let current = currentByName[name]
                return [
                    name,
                    previousState,
                    current?.permissionState.rawValue ?? "-",
                    current.map { privacy.displayPath($0.path) } ?? "-"
                ]
            }
        )
    }

    private static func signedBytes(_ bytes: Int64) -> String {
        bytes > 0 ? "+\(ByteFormat.string(bytes))" : ByteFormat.string(bytes)
    }

    private static func signedInt(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
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
