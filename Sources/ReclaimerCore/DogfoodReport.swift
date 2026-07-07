import Foundation

public struct DogfoodReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let preset: ScanScopePreset
    public let markdown: String
    public let findingCount: Int
    public let selectedDryRunCount: Int
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        preset: ScanScopePreset,
        markdown: String,
        findingCount: Int,
        selectedDryRunCount: Int,
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.preset = preset
        self.markdown = markdown
        self.findingCount = findingCount
        self.selectedDryRunCount = selectedDryRunCount
        self.nonClaims = nonClaims
    }
}

public enum DogfoodReportBuilder {
    public static func build(
        preset: ScanScopePreset,
        overview: ScanOverview,
        queues: ReviewQueueReport,
        plan: ReclaimPlan,
        activeFileReport: ActiveFileReviewReport,
        permissionReport: PermissionAdvisorReport,
        diskStatus: DiskStatusSnapshot,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> DogfoodReport {
        let id = UUID().uuidString
        let nonClaims = [
            "No cleanup was executed by this dogfood report.",
            "This report does not grant macOS permissions or Full Disk Access.",
            "APFS, snapshots, purgeable space, and open files mean Ryddi cannot promise exact free-space gains from scan-time sizes."
        ]
        let markdown = markdown(
            id: id,
            createdAt: now,
            preset: preset,
            overview: overview,
            queues: queues,
            plan: plan,
            activeFileReport: activeFileReport,
            permissionReport: permissionReport,
            diskStatus: diskStatus,
            privacy: privacy,
            nonClaims: nonClaims
        )
        return DogfoodReport(
            id: id,
            createdAt: now,
            preset: preset,
            markdown: markdown,
            findingCount: overview.findingCount,
            selectedDryRunCount: plan.items.filter(\.selected).count,
            nonClaims: nonClaims
        )
    }

    private static func markdown(
        id: String,
        createdAt: Date,
        preset: ScanScopePreset,
        overview: ScanOverview,
        queues: ReviewQueueReport,
        plan: ReclaimPlan,
        activeFileReport: ActiveFileReviewReport,
        permissionReport: PermissionAdvisorReport,
        diskStatus: DiskStatusSnapshot,
        privacy: ReportPrivacyOptions,
        nonClaims: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("# Ryddi Dogfood Report")
        lines.append("")
        lines.append("- Report id: `\(id)`")
        lines.append("- Generated: \(isoString(createdAt))")
        lines.append("- Preset: \(preset.label)")
        lines.append("")

        lines.append("## Disk Status")
        lines.append(table(headers: ["Metric", "Value"], rows: [
            ["Path", privacy.displayPath(diskStatus.path)],
            ["Pressure", diskStatus.pressure.label],
            ["Free", diskStatus.statusLine]
        ]))
        lines.append("")

        lines.append("## Scan Coverage")
        lines.append(table(
            headers: ["State", "Scope", "Path"],
            rows: overview.scopeSummaries.map {
                [$0.permissionState.rawValue, $0.name, privacy.displayPath($0.path)]
            }
        ))
        lines.append("")

        lines.append("## Top Owners")
        lines.append(table(
            headers: ["Owner", "Allocated", "Auto-safe", "Review", "Protected"],
            rows: overview.ownerSummaries.prefix(12).map {
                [
                    $0.ownerName,
                    ByteFormat.string($0.allocatedSize),
                    ByteFormat.string($0.expectedAutoSafeBytes),
                    ByteFormat.string($0.reviewBytes),
                    ByteFormat.string($0.protectedBytes)
                ]
            }
        ))
        lines.append("")

        lines.append("## Review Queues")
        lines.append(table(
            headers: ["Queue", "Items", "Allocated", "Reclaim", "Guidance"],
            rows: queues.queues.map {
                [
                    $0.title,
                    "\($0.count)",
                    ByteFormat.string($0.allocatedSize),
                    ByteFormat.string($0.estimatedImmediateReclaim),
                    $0.guidance
                ]
            }
        ))
        lines.append("")

        lines.append("## Selected Dry-Run Summary")
        lines.append(table(headers: ["Metric", "Value"], rows: [
            ["Plan id", plan.id],
            ["Mode", plan.mode],
            ["Items", "\(plan.items.count)"],
            ["Selected", "\(plan.items.filter(\.selected).count)"],
            ["Expected immediate reclaim", ByteFormat.string(plan.expectedImmediateReclaim)]
        ]))
        if !plan.dryRunSummary.isEmpty {
            lines.append("")
            for line in plan.dryRunSummary.prefix(12) {
                lines.append("- \(line)")
            }
        }
        lines.append("")

        lines.append("## Active-Handle Summary")
        lines.append(table(headers: ["Metric", "Value"], rows: [
            ["Open candidates", "\(activeFileReport.openCount)"],
            ["Check failures", "\(activeFileReport.failedCheckCount)"],
            ["Blocked bytes", ByteFormat.string(activeFileReport.totalBlockedBytes)]
        ]))
        lines.append("")

        lines.append("## Protected Buckets")
        lines.append(table(
            headers: ["Bucket", "Items", "Allocated"],
            rows: overview.safetySummaries
                .filter { $0.name == SafetyClass.preserveByDefault.label || $0.name == SafetyClass.neverTouch.label }
                .map { [$0.name, "\($0.count)", ByteFormat.string($0.allocatedSize)] }
        ))
        lines.append("")

        lines.append("## Permission Advisory")
        lines.append(table(headers: ["Metric", "Value"], rows: [
            ["Coverage", permissionReport.coverageLevel.label],
            ["Readable", "\(permissionReport.readableCount)/\(permissionReport.totalCount)"],
            ["Denied", "\(permissionReport.deniedCount)"],
            ["Missing", "\(permissionReport.missingCount)"]
        ]))
        if !permissionReport.recommendedActions.isEmpty {
            lines.append("")
            lines.append("Recommended permission actions:")
            for action in permissionReport.recommendedActions {
                lines.append("- \(action)")
            }
        }
        lines.append("")

        lines.append("## Non-Claims")
        for note in nonClaims {
            lines.append("- \(note)")
        }
        if privacy.pathStyle != .full || privacy.redactUserText {
            lines.append("- Path privacy was applied using \(privacy.summary); local audit files may still contain full paths.")
        }
        return lines.joined(separator: "\n")
    }

    private static func table(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }
        var lines = [
            "| " + headers.joined(separator: " | ") + " |",
            "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        ]
        if rows.isEmpty {
            lines.append("| " + headers.enumerated().map { index, _ in index == 0 ? "None" : "" }.joined(separator: " | ") + " |")
        } else {
            lines.append(contentsOf: rows.map { row in
                let padded = headers.indices.map { index in
                    index < row.count ? escape(row[index]) : ""
                }
                return "| " + padded.joined(separator: " | ") + " |"
            })
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
