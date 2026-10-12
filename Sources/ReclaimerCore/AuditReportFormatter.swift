import Foundation

public struct AuditReportFormatter {
    public static func plainText(report: AuditReport) -> String {
        let fmt = ByteCountFormatter()
        var lines: [String] = []
        let root = report.scannedPaths.first ?? "Unknown"
        lines.append("=== Ryddi Deep Audit: \(root) ===")
        lines.append("Scanned: \(report.scannedPaths.count) paths")
        if report.coverage.isEmpty { lines.append("Coverage: unverified (legacy report)") }
        for coverage in report.coverage { lines.append("Coverage: \(coverage.summary)") }
        if !report.hasCompleteCoverage { lines.append("Warning: coverage is incomplete or unverified. Automatic cleanup is unavailable.") }
        lines.append("Unique logical candidate estimate: \(fmt.string(fromByteCount: report.storageEstimate.logicalBytes))")
        lines.append(LogicalStorageEstimate.uncertainty)
        if report.storageEstimate.saturated { lines.append("Estimate exceeded the supported byte range; total is capped.") }
        lines.append("")
        lines.append("| Rank | Category          | Location                           | Size    | Safety | Action           |")
        lines.append("|------|-------------------|------------------------------------|---------|--------|------------------|")
        let sorted = report.recommendations.sorted { $0.impactScore > $1.impactScore }
        for (i, rec) in sorted.enumerated() {
            let rank = String(i + 1).padding(toLength: 4, withPad: " ", startingAt: 0)
            let cat = rec.category.rawValue.padding(toLength: 17, withPad: " ", startingAt: 0)
            let loc = rec.path.padding(toLength: 34, withPad: " ", startingAt: 0)
            let sz = fmt.string(fromByteCount: rec.reclaimableBytes).padding(toLength: 7, withPad: " ", startingAt: 0)
            let safe = (rec.safetyScore >= 0.8 ? "High" : rec.safetyScore >= 0.5 ? "Med" : "Low").padding(toLength: 6, withPad: " ", startingAt: 0)
            let act = actionLabel(rec.action).padding(toLength: 16, withPad: " ", startingAt: 0)
            lines.append("| \(rank) | \(cat) | \(loc) | \(sz) | \(safe) | \(act) |")
        }
        lines.append("")
        lines.append("Eligible to move to Trash (logical): \(fmt.string(fromByteCount: report.safeToReclaimBytes))")
        lines.append("Requires review (logical): \(fmt.string(fromByteCount: report.needsReviewBytes))")
        lines.append("Eligible and review subtotals can overlap; do not add them. Each finding's size is logical.")
        return lines.joined(separator: "\n")
    }

    public static func json(report: AuditReport) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(report)) ?? Data()
    }

    private static func actionLabel(_ action: ReclaimAction) -> String {
        switch action {
        case .moveToTrash: return "Move to Trash"
        case .runCommand(let cmd): return "Run: \(cmd)"
        case .reviewRequired: return "Review Required"
        }
    }
}
