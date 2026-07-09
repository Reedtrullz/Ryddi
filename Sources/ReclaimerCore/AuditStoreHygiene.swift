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

    public init(olderThanDays: Int = 30, keepRecent: Int = 100) {
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
    public let filesystemIdentity: FilesystemIdentity?

    public init(
        path: String,
        kind: String,
        bytes: Int64,
        modifiedAt: Date?,
        filesystemIdentity: FilesystemIdentity? = nil
    ) {
        self.path = path
        self.kind = kind
        self.bytes = bytes
        self.modifiedAt = modifiedAt
        self.filesystemIdentity = filesystemIdentity
    }
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
    public let deletedFileIDs: [String]
    public let errors: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        dryRun: Bool,
        planID: String,
        deletedCount: Int,
        deletedBytes: Int64,
        deletedFileIDs: [String] = [],
        errors: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.dryRun = dryRun
        self.planID = planID
        self.deletedCount = deletedCount
        self.deletedBytes = deletedBytes
        self.deletedFileIDs = deletedFileIDs
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case dryRun
        case planID
        case deletedCount
        case deletedBytes
        case deletedFileIDs
        case errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.dryRun = try container.decode(Bool.self, forKey: .dryRun)
        self.planID = try container.decode(String.self, forKey: .planID)
        self.deletedCount = try container.decode(Int.self, forKey: .deletedCount)
        self.deletedBytes = try container.decode(Int64.self, forKey: .deletedBytes)
        self.deletedFileIDs = try container.decodeIfPresent([String].self, forKey: .deletedFileIDs) ?? []
        self.errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
    }
}
