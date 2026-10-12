import Foundation

public enum BloatCategory: String, Codable, Hashable, Sendable {
    case buildArtifact, dependencyCache, oldLog, aiSessionCache, duplicateFile,
         oldInstaller, xcodeCruft, dockerLayer, trashOld, largeBinary, gitBloat
}

public enum ReclaimAction: Hashable, Sendable {
    case moveToTrash
    case runCommand(String)
    case reviewRequired
}

extension ReclaimAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, command
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .moveToTrash: try container.encode("moveToTrash", forKey: .kind)
        case .runCommand(let cmd): try container.encode("runCommand", forKey: .kind); try container.encode(cmd, forKey: .command)
        case .reviewRequired: try container.encode("reviewRequired", forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "moveToTrash": self = .moveToTrash
        case "runCommand": self = .runCommand(try container.decode(String.self, forKey: .command))
        case "reviewRequired": self = .reviewRequired
        default: self = .reviewRequired
        }
    }
}

public struct ReclaimRecommendation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let path: String
    public let category: BloatCategory
    public let reclaimableBytes: Int64
    public let safetyScore: Double
    public let effortScore: Double
    public var impactScore: Double {
        Double(reclaimableBytes) * safetyScore / (1.0 - effortScore * 0.5 + 0.5)
    }
    public let description: String
    public let action: ReclaimAction
    public let identity: FileIdentity?

    public init(path: String, category: BloatCategory, reclaimableBytes: Int64,
                safetyScore: Double, effortScore: Double,
                description: String, action: ReclaimAction,
                identity: FileIdentity? = nil) {
        self.id = UUID()
        self.path = path
        self.category = category
        self.reclaimableBytes = reclaimableBytes
        self.safetyScore = safetyScore
        self.effortScore = effortScore
        self.description = description
        self.action = action
        self.identity = identity
    }

    enum CodingKeys: String, CodingKey {
        case id, path, category, reclaimableBytes, safetyScore, effortScore, description, action, identity
    }
}

public struct AuditReport: Codable, Sendable {
    public let scannedPaths: [String]
    public let totalBytes: Int64
    public let bloatBytes: Int64
    public let reclaimableBytes: Int64
    public let recommendations: [ReclaimRecommendation]
    public let safeToReclaimBytes: Int64
    public let needsReviewBytes: Int64
    public let coverage: [ScanCoverage]

    public var storageEstimate: LogicalStorageEstimate {
        LogicalStorageEstimate(recommendations: recommendations)
    }

    public func selectedLogicalBytes(ids: Set<UUID>) -> Int64 {
        guard hasCompleteCoverage else { return 0 }
        return LogicalStorageEstimate(recommendations: recommendations.filter {
            ids.contains($0.id) && $0.safetyScore >= 0.8 && $0.action == .moveToTrash
        }).logicalBytes
    }

    public var hasCompleteCoverage: Bool {
        !coverage.isEmpty && coverage.allSatisfy { $0.status == .complete }
    }

    public init(scannedPaths: [String], totalBytes: Int64, bloatBytes: Int64,
                reclaimableBytes: Int64, recommendations: [ReclaimRecommendation],
                coverage: [ScanCoverage] = []) {
        self.scannedPaths = scannedPaths
        // Keep the legacy initializer/JSON keys readable, but never trust additive totals.
        let unique = LogicalStorageEstimate(recommendations: recommendations).logicalBytes
        self.totalBytes = unique
        self.bloatBytes = unique
        self.recommendations = recommendations
        self.coverage = coverage
        let complete = !coverage.isEmpty && coverage.allSatisfy { $0.status == .complete }
        self.safeToReclaimBytes = complete ? LogicalStorageEstimate(recommendations: recommendations.filter {
            $0.safetyScore >= 0.8 && $0.action == .moveToTrash
        }).logicalBytes : 0
        self.reclaimableBytes = safeToReclaimBytes
        self.needsReviewBytes = LogicalStorageEstimate(recommendations: recommendations.filter {
            !complete || $0.safetyScore < 0.8 || $0.action != .moveToTrash
        }).logicalBytes
    }

    public init(scannedPaths: [String], recommendations: [ReclaimRecommendation], coverage: [ScanCoverage]) {
        self.init(scannedPaths: scannedPaths, totalBytes: 0, bloatBytes: 0, reclaimableBytes: 0,
                  recommendations: recommendations, coverage: coverage)
    }

    enum CodingKeys: String, CodingKey {
        case scannedPaths, totalBytes, bloatBytes, reclaimableBytes, recommendations
        case safeToReclaimBytes, needsReviewBytes, coverage
        case storageEstimate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scannedPaths, forKey: .scannedPaths)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(bloatBytes, forKey: .bloatBytes)
        try container.encode(reclaimableBytes, forKey: .reclaimableBytes)
        try container.encode(recommendations, forKey: .recommendations)
        try container.encode(safeToReclaimBytes, forKey: .safeToReclaimBytes)
        try container.encode(needsReviewBytes, forKey: .needsReviewBytes)
        try container.encode(coverage, forKey: .coverage)
        try container.encode(storageEstimate, forKey: .storageEstimate)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(scannedPaths: try container.decode([String].self, forKey: .scannedPaths),
                  totalBytes: try container.decode(Int64.self, forKey: .totalBytes),
                  bloatBytes: try container.decode(Int64.self, forKey: .bloatBytes),
                  reclaimableBytes: try container.decode(Int64.self, forKey: .reclaimableBytes),
                  recommendations: try container.decode([ReclaimRecommendation].self, forKey: .recommendations),
                  coverage: try container.decodeIfPresent([ScanCoverage].self, forKey: .coverage) ?? [])
    }
}
