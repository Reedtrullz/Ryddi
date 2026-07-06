import Foundation

public struct ExecutionReceiptReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let title: String
    public let markdown: String
    public let receiptID: String
    public let actionCount: Int
    public let dryRunCount: Int
    public let doneCount: Int
    public let skippedCount: Int
    public let errorCount: Int
    public let totalReclaimedBytes: Int64
    public let freeSpaceDeltaBytes: Int64?
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        title: String,
        markdown: String,
        receiptID: String,
        actionCount: Int,
        dryRunCount: Int,
        doneCount: Int,
        skippedCount: Int,
        errorCount: Int,
        totalReclaimedBytes: Int64,
        freeSpaceDeltaBytes: Int64?,
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.markdown = markdown
        self.receiptID = receiptID
        self.actionCount = actionCount
        self.dryRunCount = dryRunCount
        self.doneCount = doneCount
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.totalReclaimedBytes = totalReclaimedBytes
        self.freeSpaceDeltaBytes = freeSpaceDeltaBytes
        self.nonClaims = nonClaims
    }
}

public enum ExecutionReceiptReportBuilder {
    public static func build(
        title: String = "Ryddi Receipt Report",
        receipt: ExecutionReceipt,
        privacy: ReportPrivacyOptions = .default,
        now: Date = Date()
    ) -> ExecutionReceiptReport {
        var nonClaims = [
            "This report summarizes a saved receipt; it does not execute cleanup.",
            "Dry-run reclaimed bytes are estimates, not verified free-space gains.",
            "Filesystem free-space deltas can differ from action totals because of APFS snapshots, purgeable storage, clones, caches, and concurrent system activity.",
            "Skipped and error actions require review before retrying.",
            "A receipt proves what Ryddi recorded locally, not that macOS granted broader permissions or that external native tools changed state."
        ]
        if privacy.pathStyle != .full || privacy.redactUserText {
            nonClaims.append("Report privacy was applied (\(privacy.summary)); saved local receipts may still contain full original paths.")
        }
        let id = UUID().uuidString
        let dryRunCount = receipt.actions.filter { $0.status == "dry-run" }.count
        let doneCount = receipt.actions.filter { $0.status == "done" }.count
        let skippedCount = receipt.actions.filter { $0.status == "skipped" }.count
        let errorCount = receipt.actions.filter { $0.status == "error" }.count + receipt.errors.count
        let totalReclaimed = receipt.actions.reduce(0) { $0 + $1.reclaimedBytes }
        let delta = receipt.beforeFreeBytes.flatMap { before in
            receipt.afterFreeBytes.map { $0 - before }
        }
        let markdown = markdown(
            id: id,
            title: title,
            createdAt: now,
            receipt: receipt,
            dryRunCount: dryRunCount,
            doneCount: doneCount,
            skippedCount: skippedCount,
            errorCount: errorCount,
            totalReclaimed: totalReclaimed,
            freeSpaceDelta: delta,
            privacy: privacy,
            nonClaims: nonClaims
        )
        return ExecutionReceiptReport(
            id: id,
            createdAt: now,
            title: title,
            markdown: markdown,
            receiptID: receipt.id,
            actionCount: receipt.actions.count,
            dryRunCount: dryRunCount,
            doneCount: doneCount,
            skippedCount: skippedCount,
            errorCount: errorCount,
            totalReclaimedBytes: totalReclaimed,
            freeSpaceDeltaBytes: delta,
            nonClaims: nonClaims
        )
    }

    private static func markdown(
        id: String,
        title: String,
        createdAt: Date,
        receipt: ExecutionReceipt,
        dryRunCount: Int,
        doneCount: Int,
        skippedCount: Int,
        errorCount: Int,
        totalReclaimed: Int64,
        freeSpaceDelta: Int64?,
        privacy: ReportPrivacyOptions,
        nonClaims: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append("- Report id: `\(id)`")
        lines.append("- Generated: \(isoString(createdAt))")
        lines.append("- Receipt id: `\(receipt.id)`")
        lines.append("- Receipt created: \(isoString(receipt.createdAt))")
        lines.append("")

        lines.append("## Summary")
        var rows = [
            ["Mode", receipt.mode],
            ["Rule version", receipt.ruleVersion],
            ["User confirmed", receipt.userConfirmed ? "yes" : "no"],
            ["Actions", "\(receipt.actions.count)"],
            ["Dry-run actions", "\(dryRunCount)"],
            ["Done actions", "\(doneCount)"],
            ["Skipped actions", "\(skippedCount)"],
            ["Errors", "\(errorCount)"],
            ["Recorded reclaimed bytes", ByteFormat.string(totalReclaimed)]
        ]
        if let before = receipt.beforeFreeBytes {
            rows.append(["Before free", ByteFormat.string(before)])
        }
        if let after = receipt.afterFreeBytes {
            rows.append(["After free", ByteFormat.string(after)])
        }
        if let freeSpaceDelta {
            rows.append(["Free-space delta", ByteFormat.string(freeSpaceDelta)])
        }
        lines.append(table(headers: ["Metric", "Value"], rows: rows))
        lines.append("")

        lines.append("## Actions")
        if receipt.actions.isEmpty {
            lines.append("No selected actions were recorded.")
        } else {
            let knownPaths = receipt.actions.map(\.path)
            lines.append(table(
                headers: ["Status", "Action", "Reclaimed", "Path", "Message"],
                rows: receipt.actions.map {
                    [
                        $0.status,
                        $0.action.label,
                        ByteFormat.string($0.reclaimedBytes),
                        privacy.displayPath($0.path),
                        privacy.displayText($0.message, knownPaths: knownPaths)
                    ]
                }
            ))
        }
        lines.append("")

        if !receipt.errors.isEmpty {
            lines.append("## Errors")
            let knownPaths = receipt.actions.map(\.path)
            for error in receipt.errors {
                lines.append("- \(privacy.displayText(error, knownPaths: knownPaths))")
            }
            lines.append("")
        }

        lines.append("## Explicit Non-Claims")
        for nonClaim in nonClaims {
            lines.append("- \(nonClaim)")
        }
        lines.append("")

        return lines.joined(separator: "\n")
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
