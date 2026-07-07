import Foundation

public struct ActiveFileReviewOptions: Codable, Hashable, Sendable {
    public let limit: Int
    public let includeCheckFailures: Bool

    public init(limit: Int = 40, includeCheckFailures: Bool = true) {
        self.limit = max(1, limit)
        self.includeCheckFailures = includeCheckFailures
    }
}

public enum ActiveFileReviewState: String, Codable, Hashable, Sendable {
    case open
    case checkFailed

    public var label: String {
        switch self {
        case .open: "Open"
        case .checkFailed: "Check failed"
        }
    }
}

public struct ActiveFileReviewItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { finding.id + ":" + state.rawValue }
    public let finding: Finding
    public let state: ActiveFileReviewState
    public let processSummary: [String]
    public let checkFailed: String?
    public let checkedAt: Date
    public let guidance: [String]

    public init(
        finding: Finding,
        state: ActiveFileReviewState,
        processSummary: [String],
        checkFailed: String?,
        checkedAt: Date,
        guidance: [String]
    ) {
        self.finding = finding
        self.state = state
        self.processSummary = processSummary
        self.checkFailed = checkFailed
        self.checkedAt = checkedAt
        self.guidance = guidance
    }
}

public struct ActiveFileReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let candidateCount: Int
    public let checkedCount: Int
    public let truncated: Bool
    public let items: [ActiveFileReviewItem]
    public let totalBlockedBytes: Int64
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        candidateCount: Int,
        checkedCount: Int,
        truncated: Bool,
        items: [ActiveFileReviewItem],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.candidateCount = candidateCount
        self.checkedCount = checkedCount
        self.truncated = truncated
        self.items = items
        self.totalBlockedBytes = items.reduce(0) { $0 + $1.finding.allocatedSize }
        self.nonClaims = nonClaims
    }

    public var openCount: Int {
        items.filter { $0.state == .open }.count
    }

    public var failedCheckCount: Int {
        items.filter { $0.state == .checkFailed }.count
    }
}

public final class ActiveFileReviewScanner: @unchecked Sendable {
    private let openFileChecker: OpenFileChecking

    public init(openFileChecker: OpenFileChecking = LsofOpenFileChecker()) {
        self.openFileChecker = openFileChecker
    }

    public func review(
        findings: [Finding],
        options: ActiveFileReviewOptions = ActiveFileReviewOptions()
    ) -> ActiveFileReviewReport {
        let candidates = Self.candidateFindings(from: findings)
        let checked = Array(candidates.prefix(options.limit))
        let items = checked.compactMap { finding -> ActiveFileReviewItem? in
            let status = openFileChecker.status(for: URL(fileURLWithPath: finding.path))
            let findingWithStatus = finding.withOpenFileStatus(status)
            if status.isOpen {
                return ActiveFileReviewItem(
                    finding: findingWithStatus,
                    state: .open,
                    processSummary: status.processSummary,
                    checkFailed: nil,
                    checkedAt: status.checkedAt,
                    guidance: guidance(forOpenStatus: status)
                )
            }
            if options.includeCheckFailures, let failure = status.checkFailed {
                return ActiveFileReviewItem(
                    finding: findingWithStatus,
                    state: .checkFailed,
                    processSummary: status.processSummary,
                    checkFailed: failure,
                    checkedAt: status.checkedAt,
                    guidance: guidance(forFailure: failure)
                )
            }
            return nil
        }

        return ActiveFileReviewReport(
            candidateCount: candidates.count,
            checkedCount: checked.count,
            truncated: candidates.count > checked.count,
            items: items,
            nonClaims: [
                "This report only checks cleanup-relevant candidate paths from the current scan input.",
                "Ryddi did not quit processes, execute cleanup, or modify files while building this report.",
                "An open handle does not prove a file is safe to remove after quitting; rerun Plan or Dry Run after processes close.",
                "A failed open-file check means Ryddi could not prove the path is inactive."
            ]
        )
    }

    public static func candidateFindings(from findings: [Finding]) -> [Finding] {
        findings
            .filter(isCandidate)
            .sorted { lhs, rhs in
                if lhs.allocatedSize == rhs.allocatedSize {
                    return lhs.path < rhs.path
                }
                return lhs.allocatedSize > rhs.allocatedSize
            }
    }

    public static func isCandidate(_ finding: Finding) -> Bool {
        guard !finding.isSymbolicLink else { return false }
        guard [.autoSafe, .safeAfterCondition].contains(finding.safetyClass) else { return false }
        return [.deleteCache, .trash, .compress, .quarantineHold].contains(finding.actionKind)
    }

    private func guidance(forOpenStatus status: OpenFileStatus) -> [String] {
        var lines = [
            "Quit the listed app or process, then rerun Plan or Dry Run before reclaim.",
            "If the process is unfamiliar or system-owned, leave the path untouched and inspect it manually."
        ]
        if status.checkedRecursively {
            lines.insert("Directory tree was checked recursively with lsof.", at: 0)
        }
        if !status.processSummary.isEmpty {
            lines.insert("Open by: \(status.processSummary.joined(separator: ", "))", at: 0)
        }
        return lines
    }

    private func guidance(forFailure failure: String) -> [String] {
        [
            "Open-file check failed: \(failure)",
            "Keep this path out of cleanup until the check succeeds or you have reviewed it manually."
        ]
    }
}
