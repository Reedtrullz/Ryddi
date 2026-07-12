import Foundation

public enum ScanCoverageState: String, Codable, CaseIterable, Hashable, Sendable {
    case complete
    case bounded
    case degraded

    public var label: String {
        switch self {
        case .complete: "Complete"
        case .bounded: "Bounded"
        case .degraded: "Degraded"
        }
    }
}

public struct ScanCoverage: Codable, Hashable, Sendable {
    public let state: ScanCoverageState
    public let requestedItemBudget: Int
    public let measuredItemCount: Int
    public let skippedItemCount: Int
    public let rootsVisited: Int
    public let rootsDenied: Int
    public let maximumMeasurementDepth: Int
    public let evidence: [String]

    public init(
        state: ScanCoverageState,
        requestedItemBudget: Int,
        measuredItemCount: Int,
        skippedItemCount: Int,
        rootsVisited: Int,
        rootsDenied: Int,
        maximumMeasurementDepth: Int,
        evidence: [String] = []
    ) {
        self.state = state
        self.requestedItemBudget = requestedItemBudget
        self.measuredItemCount = measuredItemCount
        self.skippedItemCount = skippedItemCount
        self.rootsVisited = rootsVisited
        self.rootsDenied = rootsDenied
        self.maximumMeasurementDepth = maximumMeasurementDepth
        self.evidence = evidence
    }

    public var nonClaim: String {
        switch state {
        case .complete:
            return "Scan coverage is complete for the requested roots and configured measurement depth. Filesystem reclaim can still differ from estimates."
        case .bounded:
            return "Scan coverage is bounded by the measurement budget; totals are estimates until a targeted rescan completes."
        case .degraded:
            return "Scan coverage is degraded because one or more roots could not be read; inaccessible storage is not represented."
        }
    }
}

public struct ScanResult: Codable, Hashable, Sendable {
    public let findings: [Finding]
    public let coverage: ScanCoverage

    public init(findings: [Finding], coverage: ScanCoverage) {
        self.findings = findings
        self.coverage = coverage
    }
}
