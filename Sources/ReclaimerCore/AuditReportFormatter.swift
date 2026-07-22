import Foundation

public struct AuditReportFormatter {
    public static func plainText(report: AuditReport) -> String {
        let fmt = ByteCountFormatter()
        var lines: [String] = []
        let root = report.scannedPaths.first ?? "Unknown"
        lines.append("=== Ryddi Deep Audit: \(root) ===")
        lines.append("Scanned: \(report.scannedPaths.count) paths")
        lines.append("Total bloat found: \(fmt.string(fromByteCount: report.bloatBytes))")
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
        lines.append("Safe to reclaim now: \(fmt.string(fromByteCount: report.safeToReclaimBytes)) (items marked High safety)")
        lines.append("Requires review: \(fmt.string(fromByteCount: report.needsReviewBytes))")
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
