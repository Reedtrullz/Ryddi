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

public struct ScanScopeCoverage: Codable, Hashable, Sendable {
    public let scopeName: String
    public let rootPath: String
    public let state: ScanCoverageState
    public let measuredItemCount: Int
    public let skippedItemCount: Int
    public let deepestMeasuredLevel: Int
    public let evidence: [String]

    public init(
        scopeName: String,
        rootPath: String,
        state: ScanCoverageState,
        measuredItemCount: Int,
        skippedItemCount: Int,
        deepestMeasuredLevel: Int,
        evidence: [String]
    ) {
        self.scopeName = scopeName
        self.rootPath = rootPath
        self.state = state
        self.measuredItemCount = measuredItemCount
        self.skippedItemCount = skippedItemCount
        self.deepestMeasuredLevel = deepestMeasuredLevel
        self.evidence = evidence
    }
}

public struct ScanCoverage: Codable, Hashable, Sendable {
    public let state: ScanCoverageState
    public let requestedItemBudget: Int
    public let measuredItemCount: Int
    public let skippedItemCount: Int
    public let rootsVisited: Int
    public let rootsDenied: Int
    public let rootsMissing: Int
    public let rootsPermissionDenied: Int
    public let maximumMeasurementDepth: Int
    public let evidence: [String]
    public let scopeCoverage: [ScanScopeCoverage]

    public init(
        state: ScanCoverageState,
        requestedItemBudget: Int,
        measuredItemCount: Int,
        skippedItemCount: Int,
        rootsVisited: Int,
        rootsDenied: Int,
        maximumMeasurementDepth: Int,
        rootsMissing: Int = 0,
        rootsPermissionDenied: Int? = nil,
        evidence: [String] = [],
        scopeCoverage: [ScanScopeCoverage] = []
    ) {
        let permissionDenied = rootsPermissionDenied ?? rootsDenied
        self.state = state
        self.requestedItemBudget = requestedItemBudget
        self.measuredItemCount = measuredItemCount
        self.skippedItemCount = skippedItemCount
        self.rootsVisited = rootsVisited
        self.rootsDenied = permissionDenied
        self.rootsMissing = rootsMissing
        self.rootsPermissionDenied = permissionDenied
        self.maximumMeasurementDepth = maximumMeasurementDepth
        self.evidence = evidence
        self.scopeCoverage = scopeCoverage
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case requestedItemBudget
        case measuredItemCount
        case skippedItemCount
        case rootsVisited
        case rootsDenied
        case rootsMissing
        case rootsPermissionDenied
        case maximumMeasurementDepth
        case evidence
        case scopeCoverage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(ScanCoverageState.self, forKey: .state)
        requestedItemBudget = try container.decode(Int.self, forKey: .requestedItemBudget)
        measuredItemCount = try container.decode(Int.self, forKey: .measuredItemCount)
        skippedItemCount = try container.decode(Int.self, forKey: .skippedItemCount)
        rootsVisited = try container.decode(Int.self, forKey: .rootsVisited)
        rootsDenied = try container.decode(Int.self, forKey: .rootsDenied)
        rootsMissing = try container.decodeIfPresent(Int.self, forKey: .rootsMissing) ?? 0
        rootsPermissionDenied = try container.decodeIfPresent(Int.self, forKey: .rootsPermissionDenied) ?? 0
        maximumMeasurementDepth = try container.decode(Int.self, forKey: .maximumMeasurementDepth)
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        scopeCoverage = try container.decodeIfPresent(
            [ScanScopeCoverage].self,
            forKey: .scopeCoverage
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(requestedItemBudget, forKey: .requestedItemBudget)
        try container.encode(measuredItemCount, forKey: .measuredItemCount)
        try container.encode(skippedItemCount, forKey: .skippedItemCount)
        try container.encode(rootsVisited, forKey: .rootsVisited)
        try container.encode(rootsPermissionDenied, forKey: .rootsDenied)
        try container.encode(rootsMissing, forKey: .rootsMissing)
        try container.encode(rootsPermissionDenied, forKey: .rootsPermissionDenied)
        try container.encode(maximumMeasurementDepth, forKey: .maximumMeasurementDepth)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(scopeCoverage, forKey: .scopeCoverage)
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
