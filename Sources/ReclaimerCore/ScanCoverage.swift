import Foundation

public enum ScanCoverageStatus: String, Codable, Sendable {
    case complete, partial, failed, skipped
}

public struct ScanCoverage: Codable, Sendable, Equatable {
    public let path: String
    public let status: ScanCoverageStatus
    public let reasons: [String]

    public init(path: String, status: ScanCoverageStatus, reasons: [String] = []) {
        self.path = path
        self.status = status
        self.reasons = Array(reasons.prefix(32))
    }

    public var summary: String {
        "\(path): \(status.rawValue)" + (reasons.isEmpty ? "" : " — " + reasons.joined(separator: "; "))
    }
}

public enum ScanCoverageError: LocalizedError, Sendable {
    case incomplete([ScanCoverage])

    public var errorDescription: String? {
        switch self {
        case .incomplete(let coverage):
            "Incomplete scan. Nothing was changed. " + coverage.filter { $0.status != .complete }.map(\.summary).joined(separator: "\n")
        }
    }
}

public struct FastScanResult: Sendable {
    public let items: [ScanItem]
    public let coverage: [ScanCoverage]
}

public struct DeepAuditResult: Sendable {
    public let recommendations: [ReclaimRecommendation]
    public let coverage: ScanCoverage
}

func reviewOnly(_ recommendations: [ReclaimRecommendation]) -> [ReclaimRecommendation] {
    recommendations.map {
        ReclaimRecommendation(path: $0.path, category: $0.category,
                              reclaimableBytes: $0.reclaimableBytes,
                              safetyScore: min($0.safetyScore, 0.5), effortScore: $0.effortScore,
                              description: $0.description + " Incomplete scan coverage; review only.",
                              action: .reviewRequired, identity: $0.identity)
    }
}
