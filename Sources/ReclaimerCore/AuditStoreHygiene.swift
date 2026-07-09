import Foundation

public struct AuditStoreSummaryItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { kind }
    public let kind: String
    public let fileCount: Int
    public let totalBytes: Int64
    public let latestModifiedAt: Date?
}

public struct AuditStoreSummary: Codable, Hashable, Sendable {
    public let rootPath: String
    public let totalKnownFileCount: Int
    public let totalKnownBytes: Int64
    public let unknownFileCount: Int
    public let symlinkCount: Int
    public let items: [AuditStoreSummaryItem]
}

public struct AuditRetentionPolicy: Codable, Hashable, Sendable {
    public let olderThanDays: Int
    public let keepRecent: Int

    public init(olderThanDays: Int = 90, keepRecent: Int = 20) {
        self.olderThanDays = max(0, olderThanDays)
        self.keepRecent = max(0, keepRecent)
    }
}

public struct AuditPruneCandidate: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let kind: String
    public let bytes: Int64
    public let modifiedAt: Date?
}

public struct AuditPrunePlan: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let rootPath: String
    public let policy: AuditRetentionPolicy
    public let candidates: [AuditPruneCandidate]
    public let skippedUnknownPaths: [String]
    public let skippedSymlinkPaths: [String]

    public var candidateCount: Int { candidates.count }
    public var candidateBytes: Int64 { candidates.reduce(0) { $0 + $1.bytes } }
}

public struct AuditPruneReceipt: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let dryRun: Bool
    public let planID: String
    public let deletedCount: Int
    public let deletedBytes: Int64
    public let errors: [String]
}
