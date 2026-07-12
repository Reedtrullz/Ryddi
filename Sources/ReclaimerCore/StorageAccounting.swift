import Foundation

public enum StoragePhysicalReclaimStatus: String, Codable, Hashable, Sendable {
    case unknown
    case estimated
    case sharedCloneBacked
    case observedDelta
}

public struct StorageAccounting: Codable, Hashable, Sendable {
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let status: StoragePhysicalReclaimStatus
    public let physicalReclaimBytes: Int64?
    public let deduplicationNote: String?

    public init(
        logicalBytes: Int64,
        allocatedBytes: Int64,
        status: StoragePhysicalReclaimStatus,
        physicalReclaimBytes: Int64? = nil,
        deduplicationNote: String? = nil
    ) {
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.status = status
        self.physicalReclaimBytes = physicalReclaimBytes
        self.deduplicationNote = deduplicationNote
    }

    // Keep the plan's longer label available while the public model uses the concise `status` field.
    public init(
        logicalBytes: Int64,
        allocatedBytes: Int64,
        physicalReclaimStatus: StoragePhysicalReclaimStatus,
        physicalReclaimBytes: Int64? = nil,
        deduplicationNote: String? = nil
    ) {
        self.init(
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            status: physicalReclaimStatus,
            physicalReclaimBytes: physicalReclaimBytes,
            deduplicationNote: deduplicationNote
        )
    }

    public var physicalReclaimStatus: StoragePhysicalReclaimStatus {
        status
    }

    public var estimatedImmediateReclaimBytes: Int64 {
        switch status {
        case .unknown, .sharedCloneBacked:
            return 0
        case .observedDelta:
            return max(0, physicalReclaimBytes ?? 0)
        case .estimated:
            if let physicalReclaimBytes {
                return min(max(0, physicalReclaimBytes), max(0, allocatedBytes))
            }
            return min(max(0, logicalBytes), max(0, allocatedBytes))
        }
    }

    public static func legacyEstimate(logicalBytes: Int64, allocatedBytes: Int64) -> StorageAccounting {
        StorageAccounting(
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            status: .estimated,
            deduplicationNote: "Legacy finding: immediate reclaim is a conservative estimate from logical and allocated bytes; no post-action free-space delta was observed."
        )
    }

    public static func observedReclaimBytes(beforeFreeBytes: Int64?, afterFreeBytes: Int64?) -> Int64? {
        guard let beforeFreeBytes, let afterFreeBytes else { return nil }
        let delta = afterFreeBytes - beforeFreeBytes
        return delta > 0 ? delta : nil
    }

    private enum CodingKeys: String, CodingKey {
        case logicalBytes
        case allocatedBytes
        case status
        case physicalReclaimStatus
        case physicalReclaimBytes
        case deduplicationNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.logicalBytes = try container.decode(Int64.self, forKey: .logicalBytes)
        self.allocatedBytes = try container.decode(Int64.self, forKey: .allocatedBytes)
        self.status = try container.decodeIfPresent(StoragePhysicalReclaimStatus.self, forKey: .status)
            ?? container.decodeIfPresent(StoragePhysicalReclaimStatus.self, forKey: .physicalReclaimStatus)
            ?? .unknown
        self.physicalReclaimBytes = try container.decodeIfPresent(Int64.self, forKey: .physicalReclaimBytes)
        self.deduplicationNote = try container.decodeIfPresent(String.self, forKey: .deduplicationNote)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(logicalBytes, forKey: .logicalBytes)
        try container.encode(allocatedBytes, forKey: .allocatedBytes)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(physicalReclaimBytes, forKey: .physicalReclaimBytes)
        try container.encodeIfPresent(deduplicationNote, forKey: .deduplicationNote)
    }
}
