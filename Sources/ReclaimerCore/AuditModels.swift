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

    public init(path: String, category: BloatCategory, reclaimableBytes: Int64,
                safetyScore: Double, effortScore: Double,
                description: String, action: ReclaimAction) {
        self.id = UUID()
        self.path = path
        self.category = category
        self.reclaimableBytes = reclaimableBytes
        self.safetyScore = safetyScore
        self.effortScore = effortScore
        self.description = description
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case id, path, category, reclaimableBytes, safetyScore, effortScore, description, action
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

    public init(scannedPaths: [String], totalBytes: Int64, bloatBytes: Int64,
                reclaimableBytes: Int64, recommendations: [ReclaimRecommendation]) {
        self.scannedPaths = scannedPaths
        self.totalBytes = totalBytes
        self.bloatBytes = bloatBytes
        self.reclaimableBytes = reclaimableBytes
        self.recommendations = recommendations
        self.safeToReclaimBytes = recommendations.filter { $0.safetyScore >= 0.8 }
            .reduce(0) { $0 + $1.reclaimableBytes }
        self.needsReviewBytes = recommendations.filter { $0.safetyScore < 0.8 }
            .reduce(0) { $0 + $1.reclaimableBytes }
    }
}
