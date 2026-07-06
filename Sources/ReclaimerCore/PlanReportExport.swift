import Foundation

public struct ReclaimPlanReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let title: String
    public let markdown: String
    public let planID: String
    public let itemCount: Int
    public let selectedCount: Int
    public let blockedCount: Int
    public let expectedImmediateReclaim: Int64
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        title: String,
        markdown: String,
        planID: String,
        itemCount: Int,
        selectedCount: Int,
        blockedCount: Int,
        expectedImmediateReclaim: Int64,
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.markdown = markdown
        self.planID = planID
        self.itemCount = itemCount
        self.selectedCount = selectedCount
        self.blockedCount = blockedCount
        self.expectedImmediateReclaim = expectedImmediateReclaim
        self.nonClaims = nonClaims
    }
}

public enum ReclaimPlanReportBuilder {
    public static func build(
        title: String = "Ryddi Plan Report",
        plan: ReclaimPlan,
        itemLimit: Int = 25,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> ReclaimPlanReport {
        var nonClaims = [
            "This report summarizes a proposed reclaim plan; it does not execute cleanup.",
            "Expected reclaim uses plan-time allocated bytes and is not a promise of exact Finder or df free-space gains.",
            "Plan conditions and open-file state can change before dry-run or execution.",
            "A plan report is not a dry-run receipt and is not proof that cleanup will succeed.",
            "Protected, native-tool, report-only, and review-required items require review or owner tools rather than raw deletion."
        ]
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local plans may still contain full original paths.")
        }
        let id = UUID().uuidString
        let selectedCount = plan.items.filter(\.selected).count
        let blockedCount = plan.items.filter { !$0.selected && $0.conditions.contains { !$0.isSatisfied } }.count
        let markdown = markdown(
            id: id,
            title: title,
            createdAt: now,
            plan: plan,
            itemLimit: itemLimit,
            selectedCount: selectedCount,
            blockedCount: blockedCount,
            privacy: privacy,
            nonClaims: nonClaims
        )
        return ReclaimPlanReport(
            id: id,
            createdAt: now,
            title: title,
            markdown: markdown,
            planID: plan.id,
            itemCount: plan.items.count,
            selectedCount: selectedCount,
            blockedCount: blockedCount,
            expectedImmediateReclaim: plan.expectedImmediateReclaim,
            nonClaims: nonClaims
        )
    }

    private static func markdown(
        id: String,
        title: String,
        createdAt: Date,
        plan: ReclaimPlan,
        itemLimit: Int,
        selectedCount: Int,
        blockedCount: Int,
        privacy: ReportPrivacyOptions,
        nonClaims: [String]
    ) -> String {
        let limit = max(1, itemLimit)
        let knownPaths = plan.items.map(\.finding.path)
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append("- Report id: `\(id)`")
        lines.append("- Generated: \(isoString(createdAt))")
        lines.append("- Plan id: `\(plan.id)`")
        lines.append("- Plan created: \(isoString(plan.createdAt))")
        lines.append("")

        lines.append("## Summary")
        lines.append(table(
            headers: ["Metric", "Value"],
            rows: [
                ["Mode", plan.mode],
                ["Items", "\(plan.items.count)"],
                ["Selected items", "\(selectedCount)"],
                ["Blocked items", "\(blockedCount)"],
                ["Review-only items", "\(plan.items.count - selectedCount)"],
                ["Expected immediate reclaim", ByteFormat.string(plan.expectedImmediateReclaim)]
            ]
        ))
        lines.append("")

        lines.append("## Safety Buckets")
        lines.append(table(
            headers: ["Safety", "Items", "Selected", "Allocated", "Expected reclaim"],
            rows: safetyRows(for: plan.items)
        ))
        lines.append("")

        lines.append("## Selected Actions")
        let selectedItems = plan.items
            .filter(\.selected)
            .sorted { lhs, rhs in
                if lhs.estimatedImmediateReclaim == rhs.estimatedImmediateReclaim {
                    return lhs.finding.path < rhs.finding.path
                }
                return lhs.estimatedImmediateReclaim > rhs.estimatedImmediateReclaim
            }
        if selectedItems.isEmpty {
            lines.append("No items are selected for immediate reclaim.")
        } else {
            lines.append(table(
                headers: ["Estimate", "Action", "Safety", "Path", "Conditions"],
                rows: selectedItems.prefix(limit).map {
                    [
                        ByteFormat.string($0.estimatedImmediateReclaim),
                        $0.proposedAction.label,
                        $0.finding.safetyClass.label,
                        privacy.displayPath($0.finding.path),
                        conditionSummary($0.conditions, privacy: privacy, knownPaths: knownPaths)
                    ]
                }
            ))
            if selectedItems.count > limit {
                lines.append("")
                lines.append("Selected action list truncated to \(limit) item(s).")
            }
        }
        lines.append("")

        lines.append("## Review And Blocked Items")
        let reviewItems = plan.items
            .filter { !$0.selected }
            .sorted { lhs, rhs in
                if lhs.finding.allocatedSize == rhs.finding.allocatedSize {
                    return lhs.finding.path < rhs.finding.path
                }
                return lhs.finding.allocatedSize > rhs.finding.allocatedSize
            }
        if reviewItems.isEmpty {
            lines.append("No review-only or blocked items were recorded.")
        } else {
            lines.append(table(
                headers: ["Allocated", "Action", "Safety", "Path", "Reason"],
                rows: reviewItems.prefix(limit).map {
                    [
                        ByteFormat.string($0.finding.allocatedSize),
                        $0.proposedAction.label,
                        $0.finding.safetyClass.label,
                        privacy.displayPath($0.finding.path),
                        reviewReason($0, privacy: privacy, knownPaths: knownPaths)
                    ]
                }
            ))
            if reviewItems.count > limit {
                lines.append("")
                lines.append("Review list truncated to \(limit) item(s).")
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

    private static func safetyRows(for items: [ReclaimPlanItem]) -> [[String]] {
        SafetyClass.allCases.compactMap { safetyClass in
            let bucket = items.filter { $0.finding.safetyClass == safetyClass }
            guard !bucket.isEmpty else { return nil }
            let allocated = bucket.reduce(0) { $0 + $1.finding.allocatedSize }
            let reclaim = bucket.reduce(0) { $0 + $1.estimatedImmediateReclaim }
            return [
                safetyClass.label,
                "\(bucket.count)",
                "\(bucket.filter(\.selected).count)",
                ByteFormat.string(allocated),
                ByteFormat.string(reclaim)
            ]
        }
    }

    private static func conditionSummary(
        _ conditions: [PlanCondition],
        privacy: ReportPrivacyOptions,
        knownPaths: [String]
    ) -> String {
        guard !conditions.isEmpty else { return "No additional conditions" }
        let unsatisfied = conditions.filter { !$0.isSatisfied }
        if unsatisfied.isEmpty {
            return "All conditions satisfied"
        }
        return unsatisfied.prefix(3)
            .map { privacy.displayText($0.message, knownPaths: knownPaths) }
            .joined(separator: "; ")
    }

    private static func reviewReason(
        _ item: ReclaimPlanItem,
        privacy: ReportPrivacyOptions,
        knownPaths: [String]
    ) -> String {
        let unsatisfied = item.conditions.filter { !$0.isSatisfied }
        if let first = unsatisfied.first {
            return privacy.displayText(first.message, knownPaths: knownPaths)
        }
        switch item.finding.safetyClass {
        case .autoSafe:
            return "Not selected by current plan mode"
        case .safeAfterCondition:
            return "Requires condition or app/native-tool review"
        case .reviewRequired:
            return "Manual review required"
        case .preserveByDefault:
            return "Preserved by default"
        case .neverTouch:
            return "Never-touch protected data"
        }
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
