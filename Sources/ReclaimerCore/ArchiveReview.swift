import Foundation

public enum ArchiveReviewRecommendation: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case archive
    case trashReview
    case useCleanupPlan
    case keep
    case manualReview
    case blocked

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .archive: "Archive"
        case .trashReview: "Review for Trash"
        case .useCleanupPlan: "Use Cleanup Plan"
        case .keep: "Keep"
        case .manualReview: "Manual Review"
        case .blocked: "Blocked"
        }
    }
}

public struct ArchiveReviewRow: Codable, Hashable, Identifiable, Sendable {
    public var id: String { finding.id }
    public let finding: Finding
    public let path: String
    public let displayName: String
    public let scopeName: String
    public let category: String
    public let ownerName: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let kind: LargeOldReviewKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let ageDays: Int?
    public let recommendation: ArchiveReviewRecommendation
    public let rationale: String
    public let suggestedAction: String
    public let recovery: String
    public let blockers: [String]
    public let evidence: [String]

    public init(largeOldRow: LargeOldReviewRow) {
        let recommendation = ArchiveReviewRow.recommendation(for: largeOldRow)
        finding = largeOldRow.row.finding
        path = largeOldRow.path
        displayName = largeOldRow.displayName
        scopeName = largeOldRow.scopeName
        category = largeOldRow.category
        ownerName = largeOldRow.ownerName
        safetyClass = largeOldRow.safetyClass
        actionKind = largeOldRow.actionKind
        kind = largeOldRow.kind
        logicalSize = largeOldRow.logicalSize
        allocatedSize = largeOldRow.allocatedSize
        ageDays = largeOldRow.ageDays
        self.recommendation = recommendation
        rationale = ArchiveReviewRow.rationale(for: largeOldRow, recommendation: recommendation)
        suggestedAction = ArchiveReviewRow.suggestedAction(for: largeOldRow, recommendation: recommendation)
        recovery = ArchiveReviewRow.recovery(for: largeOldRow, recommendation: recommendation)
        blockers = ArchiveReviewRow.blockers(for: largeOldRow)
        evidence = ArchiveReviewRow.evidence(for: largeOldRow)
    }

    private static func recommendation(for row: LargeOldReviewRow) -> ArchiveReviewRecommendation {
        if row.row.finding.openFileStatus?.isOpen == true || row.row.finding.openFileStatus?.checkFailed != nil {
            return .blocked
        }
        if row.safetyClass == .neverTouch {
            return .keep
        }
        if row.safetyClass == .autoSafe, [.deleteCache, .trash].contains(row.actionKind) {
            return .useCleanupPlan
        }
        if row.safetyClass == .preserveByDefault {
            if row.actionKind == .compress && row.kind == .largeAndOld {
                return .archive
            }
            return .keep
        }
        if isLikelyInstallerOrArchive(row), [.large, .largeAndOld].contains(row.kind) {
            return .trashReview
        }
        if row.kind == .largeAndOld {
            return .archive
        }
        return .manualReview
    }

    private static func rationale(for row: LargeOldReviewRow, recommendation: ArchiveReviewRecommendation) -> String {
        let age = row.ageDays.map { " It is \($0) days old." } ?? ""
        switch recommendation {
        case .archive:
            return "This looks like a cold large item or valuable history that may be worth compressing or moving to long-term storage.\(age)"
        case .trashReview:
            return "This looks like a large downloaded installer/archive-style artifact; these are often replaceable but still need Finder review.\(age)"
        case .useCleanupPlan:
            return "This is already classified as rebuildable cleanup data, so it belongs in the normal dry-run cleanup plan rather than a manual archive checklist.\(age)"
        case .keep:
            return "This is protected, valuable, or user-owned data. Size or age alone is not enough reason to move it.\(age)"
        case .manualReview:
            return "This is a large or old review signal without enough evidence for an archive or Trash recommendation.\(age)"
        case .blocked:
            return "Ryddi saw an active-file or open-check blocker; review again after the owning app exits."
        }
    }

    private static func suggestedAction(for row: LargeOldReviewRow, recommendation: ArchiveReviewRecommendation) -> String {
        switch recommendation {
        case .archive:
            return "Open or Quick Look the item, confirm it is cold, then compress it or move it to intentional long-term storage."
        case .trashReview:
            return "Open the item in Finder, confirm it can be re-downloaded or is no longer needed, then move it to Trash manually."
        case .useCleanupPlan:
            return "Use `reclaimer plan` and `reclaimer execute --dry-run`; final cleanup still requires the normal plan and receipt gates."
        case .keep:
            return "Keep it by default, or add a user exclusion/protection rule if this path is noisy in future scans."
        case .manualReview:
            return "Inspect ownership, contents, and backups before deciding whether to keep, archive, Trash, or exclude it."
        case .blocked:
            return "Quit the owning app or resolve the open-file check failure, then rescan before making an archive or Trash decision."
        }
    }

    private static func recovery(for row: LargeOldReviewRow, recommendation: ArchiveReviewRecommendation) -> String {
        switch recommendation {
        case .archive:
            return "Recovery depends on the archive or storage location you create; Ryddi does not create it in this report."
        case .trashReview:
            return "Finder Trash may allow recovery until emptied; backups are still the safer recovery path."
        case .useCleanupPlan:
            return "Recovery follows the resulting dry-run/execution receipt, Trash, holding area, or cache rebuild guidance."
        case .keep:
            return row.row.finding.ruleMatches.first?.recovery ?? "Keep the item or restore from backup if removed manually."
        case .manualReview:
            return "Recovery depends on your manual action; verify backups before moving or compressing unique data."
        case .blocked:
            return "No action should be taken while blocked; recovery is not applicable."
        }
    }

    private static func blockers(for row: LargeOldReviewRow) -> [String] {
        guard let status = row.row.finding.openFileStatus else { return [] }
        if status.isOpen {
            let processes = status.processSummary.isEmpty ? "unknown process" : status.processSummary.joined(separator: ", ")
            return ["Open handles reported by: \(processes)."]
        }
        if let checkFailed = status.checkFailed {
            return ["Open-file check failed: \(checkFailed)."]
        }
        return []
    }

    private static func evidence(for row: LargeOldReviewRow) -> [String] {
        var output = [row.reviewReason]
        output += row.row.finding.ruleMatches.flatMap(\.evidence)
        output += row.row.finding.evidence.map(\.message)
        return Array(Set(output)).sorted()
    }

    private static func isLikelyInstallerOrArchive(_ row: LargeOldReviewRow) -> Bool {
        let lower = row.path.lowercased()
        let extensions = [
            ".dmg", ".pkg", ".mpkg", ".xip", ".iso",
            ".zip", ".tar", ".tgz", ".tar.gz", ".tar.bz2", ".tar.xz",
            ".rar", ".7z", ".gz"
        ]
        guard extensions.contains(where: { lower.hasSuffix($0) }) else { return false }
        return lower.contains("/downloads/") ||
            lower.contains("/mail downloads/") ||
            lower.contains("/desktop/") ||
            lower.contains("/.trash/")
    }
}

public struct ArchiveReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let title: String
    public let mode: LargeOldReviewMode
    public let limit: Int
    public let candidateCount: Int
    public let rowCount: Int
    public let totalAllocatedSize: Int64
    public let totalLogicalSize: Int64
    public let archiveCandidateBytes: Int64
    public let trashReviewBytes: Int64
    public let cleanupPlanBytes: Int64
    public let keepBytes: Int64
    public let blockedBytes: Int64
    public let recommendationSummaries: [BucketSummary]
    public let categorySummaries: [BucketSummary]
    public let safetySummaries: [BucketSummary]
    public let rows: [ArchiveReviewRow]
    public let markdown: String
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        title: String,
        mode: LargeOldReviewMode,
        limit: Int,
        rows: [ArchiveReviewRow],
        accountingRows: [ArchiveReviewRow],
        markdown: String,
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.mode = mode
        self.limit = limit
        candidateCount = accountingRows.count
        rowCount = rows.count
        totalAllocatedSize = accountingRows.reduce(0) { $0 + $1.allocatedSize }
        totalLogicalSize = accountingRows.reduce(0) { $0 + $1.logicalSize }
        archiveCandidateBytes = Self.bytes(in: accountingRows, recommendation: .archive)
        trashReviewBytes = Self.bytes(in: accountingRows, recommendation: .trashReview)
        cleanupPlanBytes = Self.bytes(in: accountingRows, recommendation: .useCleanupPlan)
        keepBytes = Self.bytes(in: accountingRows, recommendations: [.keep, .manualReview])
        blockedBytes = Self.bytes(in: accountingRows, recommendation: .blocked)
        recommendationSummaries = Self.bucket(accountingRows, by: { $0.recommendation.label })
        categorySummaries = Self.bucket(accountingRows, by: { $0.category })
        safetySummaries = Self.bucket(accountingRows, by: { $0.safetyClass.label })
        self.rows = rows
        self.markdown = markdown
        self.nonClaims = nonClaims
    }

    private static func bytes(in rows: [ArchiveReviewRow], recommendation: ArchiveReviewRecommendation) -> Int64 {
        bytes(in: rows, recommendations: [recommendation])
    }

    private static func bytes(in rows: [ArchiveReviewRow], recommendations: Set<ArchiveReviewRecommendation>) -> Int64 {
        rows
            .filter { recommendations.contains($0.recommendation) }
            .reduce(0) { $0 + $1.allocatedSize }
    }

    private static func bucket(
        _ rows: [ArchiveReviewRow],
        by key: (ArchiveReviewRow) -> String
    ) -> [BucketSummary] {
        Dictionary(grouping: rows, by: key)
            .map { name, items in
                BucketSummary(
                    name: name,
                    count: items.count,
                    logicalSize: items.reduce(0) { $0 + $1.logicalSize },
                    allocatedSize: items.reduce(0) { $0 + $1.allocatedSize }
                )
            }
            .sorted {
                if $0.allocatedSize == $1.allocatedSize {
                    return $0.name < $1.name
                }
                return $0.allocatedSize > $1.allocatedSize
            }
    }
}

public enum ArchiveReviewBuilder {
    public static func build(
        title: String = "Ryddi Archive Candidate Review",
        findings: [Finding],
        mode: LargeOldReviewMode = .all,
        sort: TopOffenderSort = .allocated,
        limit: Int = 25,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> ArchiveReviewReport {
        var nonClaims = [
            "This report does not compress, move, Trash, or delete files.",
            "Archive and Trash recommendations are review prompts, not cleanup permission.",
            "Large/old signals are based on scan-time metadata and can miss app-specific value, backups, cloud state, APFS clones, snapshots, or purgeable storage.",
            "Use Finder, Quick Look, backups, and the normal dry-run plan before taking destructive action.",
            "Protected, never-touch, browser profile, VM/container, creative asset, credential, config, and unknown app-state data remain review-first or keep-by-default."
        ]
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local scan data may still contain full original paths.")
        }

        let allRows = FindingAnalytics.largeOldReviewReport(
            findings: findings,
            mode: mode,
            sort: sort,
            limit: Int.max,
            now: now
        )
        .rows
        .map(ArchiveReviewRow.init(largeOldRow:))
        .sorted { lhs, rhs in
            compare(lhs, rhs, sort: sort)
        }
        let displayRows = allRows.prefix(max(0, limit)).map { $0 }
        let id = UUID().uuidString
        let markdown = markdown(
            id: id,
            title: title,
            createdAt: now,
            mode: mode,
            limit: limit,
            rows: displayRows,
            accountingRows: allRows,
            privacy: privacy,
            nonClaims: nonClaims
        )
        return ArchiveReviewReport(
            id: id,
            createdAt: now,
            title: title,
            mode: mode,
            limit: limit,
            rows: displayRows,
            accountingRows: allRows,
            markdown: markdown,
            nonClaims: nonClaims
        )
    }

    private static func markdown(
        id: String,
        title: String,
        createdAt: Date,
        mode: LargeOldReviewMode,
        limit: Int,
        rows: [ArchiveReviewRow],
        accountingRows: [ArchiveReviewRow],
        privacy: ReportPrivacyOptions,
        nonClaims: [String]
    ) -> String {
        let report = ArchiveReviewReport(
            id: id,
            createdAt: createdAt,
            title: title,
            mode: mode,
            limit: limit,
            rows: rows,
            accountingRows: accountingRows,
            markdown: "",
            nonClaims: nonClaims
        )
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append("- Report id: `\(id)`")
        lines.append("- Generated: \(isoString(createdAt))")
        lines.append("- Mode: \(mode.label)")
        lines.append("")

        lines.append("## Summary")
        lines.append(table(
            headers: ["Metric", "Value"],
            rows: [
                ["Candidates", "\(report.candidateCount)"],
                ["Rows shown", "\(report.rowCount)/\(report.limit)"],
                ["Allocated under review", ByteFormat.string(report.totalAllocatedSize)],
                ["Archive candidate bytes", ByteFormat.string(report.archiveCandidateBytes)],
                ["Trash-review bytes", ByteFormat.string(report.trashReviewBytes)],
                ["Cleanup-plan bytes", ByteFormat.string(report.cleanupPlanBytes)],
                ["Keep/manual bytes", ByteFormat.string(report.keepBytes)],
                ["Blocked bytes", ByteFormat.string(report.blockedBytes)]
            ]
        ))
        lines.append("")

        lines.append("## Recommendations")
        lines.append(summaryTable(report.recommendationSummaries))
        lines.append("")

        lines.append("## Categories")
        lines.append(summaryTable(Array(report.categorySummaries.prefix(12))))
        lines.append("")

        lines.append("## Candidate Checklist")
        if rows.isEmpty {
            lines.append("No archive candidates matched the current scan settings.")
        } else {
            lines.append(table(
                headers: ["Check", "Recommendation", "Allocated", "Age", "Safety", "Path", "Rationale"],
                rows: rows.map { row in
                    [
                        "[ ]",
                        row.recommendation.label,
                        ByteFormat.string(row.allocatedSize),
                        row.ageDays.map { "\($0)d" } ?? "-",
                        row.safetyClass.label,
                        privacy.displayPath(row.path),
                        privacy.displayText(row.rationale, knownPaths: [row.path])
                    ]
                }
            ))
        }
        lines.append("")

        lines.append("## Suggested Actions")
        for row in rows {
            lines.append("- \(row.recommendation.label): \(privacy.displayPath(row.path))")
            lines.append("  - \(privacy.displayText(row.suggestedAction, knownPaths: [row.path]))")
            lines.append("  - Recovery: \(privacy.displayText(row.recovery, knownPaths: [row.path]))")
            if !row.blockers.isEmpty {
                for blocker in row.blockers {
                    lines.append("  - Blocker: \(privacy.displayText(blocker, knownPaths: [row.path]))")
                }
            }
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

    private static func compare(
        _ lhs: ArchiveReviewRow,
        _ rhs: ArchiveReviewRow,
        sort: TopOffenderSort
    ) -> Bool {
        switch sort {
        case .age:
            let leftAge = lhs.ageDays ?? -1
            let rightAge = rhs.ageDays ?? -1
            if leftAge == rightAge {
                return compareAllocated(lhs, rhs)
            }
            return leftAge > rightAge
        case .category:
            if lhs.category == rhs.category {
                return compareAllocated(lhs, rhs)
            }
            return lhs.category < rhs.category
        case .owner:
            if lhs.ownerName == rhs.ownerName {
                return compareAllocated(lhs, rhs)
            }
            return lhs.ownerName < rhs.ownerName
        case .safety:
            if lhs.safetyClass == rhs.safetyClass {
                return compareAllocated(lhs, rhs)
            }
            return lhs.safetyClass.riskRank < rhs.safetyClass.riskRank
        case .logical:
            if lhs.logicalSize == rhs.logicalSize {
                return lhs.path < rhs.path
            }
            return lhs.logicalSize > rhs.logicalSize
        default:
            return compareAllocated(lhs, rhs)
        }
    }

    private static func compareAllocated(_ lhs: ArchiveReviewRow, _ rhs: ArchiveReviewRow) -> Bool {
        if lhs.allocatedSize == rhs.allocatedSize {
            return lhs.path < rhs.path
        }
        return lhs.allocatedSize > rhs.allocatedSize
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
