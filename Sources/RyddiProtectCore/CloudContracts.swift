import Foundation

public enum CloudProviderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case dropbox
    case googleDrive
    case mega

    public var label: String {
        switch self {
        case .dropbox: "Dropbox"
        case .googleDrive: "Google Drive"
        case .mega: "MEGA"
        }
    }
}

public enum CloudCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case readMetadata
    case readContent
    case userSelectedFiles
    case resumableSession
}

public enum CloudConnectionState: String, Codable, Hashable, Sendable {
    case disconnected
    case connected
    case degraded
    case authorizationExpired
}

public struct CloudConnectionStatus: Hashable, Sendable {
    public let state: CloudConnectionState
    public let detail: String

    public init(state: CloudConnectionState, detail: String) {
        self.state = state
        self.detail = detail
    }
}

/// Absolute monotonic deadline and response bound that every provider request must enforce.
public struct CloudRequestContext: Hashable, Sendable {
    public let deadlineUptime: TimeInterval
    public let maximumResponseBytes: Int

    public init(deadlineUptime: TimeInterval, maximumResponseBytes: Int) {
        self.deadlineUptime = deadlineUptime
        self.maximumResponseBytes = Swift.min(
            Swift.max(0, maximumResponseBytes),
            CloudInventoryLimits.maximumResponseBytes
        )
    }

    public func remainingTime(at uptime: TimeInterval) -> TimeInterval {
        let remaining = deadlineUptime - uptime
        guard remaining.isFinite, remaining > 0 else { return 0 }
        return Swift.min(remaining, CloudInventoryLimits.maximumElapsedSeconds)
    }
}

public enum CloudContractError: Error, Equatable, Sendable {
    case invalidConnectionOrdinal
    case invalidObjectIdentifier
    case invalidObjectName
    case invalidObjectSize
    case invalidResponseSize
    case invalidCursor
}

/// Persistable, non-sensitive handle used to rediscover a Keychain-backed connection.
public struct CloudConnectionLocator: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let provider: CloudProviderKind
    public let ordinal: Int

    public init(id: UUID = UUID(), provider: CloudProviderKind, ordinal: Int) throws {
        guard (1...999).contains(ordinal) else {
            throw CloudContractError.invalidConnectionOrdinal
        }
        self.id = id
        self.provider = provider
        self.ordinal = ordinal
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case ordinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            provider: container.decode(CloudProviderKind.self, forKey: .provider),
            ordinal: container.decode(Int.self, forKey: .ordinal)
        )
    }
}

/// Runtime-only connection metadata. Provider account identifiers are deliberately absent.
public struct CloudConnectionReference: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let provider: CloudProviderKind
    public let ordinal: Int
    public let connectedAt: Date
    public let grantedCapabilities: Set<CloudCapability>

    public var displayLabel: String { "\(provider.label) \(ordinal)" }

    public init(
        id: UUID = UUID(),
        provider: CloudProviderKind,
        ordinal: Int,
        connectedAt: Date = Date(),
        grantedCapabilities: Set<CloudCapability>
    ) throws {
        guard (1...999).contains(ordinal) else {
            throw CloudContractError.invalidConnectionOrdinal
        }
        self.id = id
        self.provider = provider
        self.ordinal = ordinal
        self.connectedAt = connectedAt
        self.grantedCapabilities = grantedCapabilities
    }

    public init(
        locator: CloudConnectionLocator,
        connectedAt: Date = Date(),
        grantedCapabilities: Set<CloudCapability>
    ) {
        self.id = locator.id
        self.provider = locator.provider
        self.ordinal = locator.ordinal
        self.connectedAt = connectedAt
        self.grantedCapabilities = grantedCapabilities
    }

}

public enum CloudObjectKind: String, Hashable, Sendable {
    case file
    case folder
    case nativeDocument
    case shortcut
    case unknown
}

/// Runtime-only provider metadata. This type intentionally does not conform to Codable.
public struct CloudObjectReference: Hashable, Identifiable, Sendable {
    public let id: String
    public let provider: CloudProviderKind
    public let parentID: String?
    public let displayName: String
    public let objectKind: CloudObjectKind
    public let logicalBytes: Int64?
    public let modifiedAt: Date?
    public let revision: String?
    public let providerHash: String?
    public let selectedByUser: Bool

    public init(
        id: String,
        provider: CloudProviderKind,
        parentID: String? = nil,
        displayName: String,
        objectKind: CloudObjectKind,
        logicalBytes: Int64? = nil,
        modifiedAt: Date? = nil,
        revision: String? = nil,
        providerHash: String? = nil,
        selectedByUser: Bool = false
    ) throws {
        guard Self.isBoundedText(id, maximumBytes: 2_048), !id.hasPrefix("-") else {
            throw CloudContractError.invalidObjectIdentifier
        }
        guard Self.isSafeObjectName(displayName) else {
            throw CloudContractError.invalidObjectName
        }
        guard logicalBytes.map({ $0 >= 0 }) ?? true else {
            throw CloudContractError.invalidObjectSize
        }
        if let parentID, !Self.isBoundedText(parentID, maximumBytes: 2_048) {
            throw CloudContractError.invalidObjectIdentifier
        }
        self.id = id
        self.provider = provider
        self.parentID = parentID
        self.displayName = displayName
        self.objectKind = objectKind
        self.logicalBytes = logicalBytes
        self.modifiedAt = modifiedAt
        if let revision, !Self.isBoundedText(revision, maximumBytes: 2_048) {
            throw CloudContractError.invalidObjectIdentifier
        }
        if let providerHash, !Self.isBoundedText(providerHash, maximumBytes: 512) {
            throw CloudContractError.invalidObjectIdentifier
        }
        self.revision = revision
        self.providerHash = providerHash
        self.selectedByUser = selectedByUser
    }

    private static func isSafeObjectName(_ value: String) -> Bool {
        guard isBoundedText(value, maximumBytes: 4_096) else {
            return false
        }
        let pathComponents = value.split(
            maxSplits: Int.max,
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "/" || $0 == "\\" }
        )
        return value != "."
            && !value.hasPrefix("/")
            && !value.hasPrefix("\\")
            && !pathComponents.contains(where: { $0 == ".." })
    }

    private static func isBoundedText(_ value: String, maximumBytes: Int) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              !value.contains("\0"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        return true
    }

    var canonicalMetadataByteCount: Int {
        16
            + id.utf8.count
            + (parentID?.utf8.count ?? 0)
            + displayName.utf8.count
            + (revision?.utf8.count ?? 0)
            + (providerHash?.utf8.count ?? 0)
    }
}

public struct CloudInventoryPage: Sendable {
    public let objects: [CloudObjectReference]
    public let nextCursor: String?
    public let truncated: Bool
    public let rawResponseByteCount: Int
    /// Conservative accounting: never less than the shared canonical metadata cost.
    public let responseByteCount: Int

    public init(
        objects: [CloudObjectReference],
        nextCursor: String?,
        truncated: Bool,
        responseByteCount: Int
    ) throws {
        guard objects.count <= CloudInventoryLimits.maximumPageObjects else {
            throw CloudContractError.invalidObjectSize
        }
        guard (0...CloudInventoryLimits.maximumResponseBytes).contains(responseByteCount) else {
            throw CloudContractError.invalidResponseSize
        }
        if let nextCursor {
            guard !nextCursor.isEmpty,
                  nextCursor.utf8.count <= CloudInventoryLimits.maximumCursorBytes,
                  !nextCursor.contains("\0") else {
                throw CloudContractError.invalidCursor
            }
        }
        let canonicalByteCount = 16
            + (nextCursor?.utf8.count ?? 0)
            + objects.reduce(0) { $0 + $1.canonicalMetadataByteCount }
        let accountedByteCount = Swift.max(responseByteCount, canonicalByteCount)
        guard accountedByteCount <= CloudInventoryLimits.maximumResponseBytes else {
            throw CloudContractError.invalidResponseSize
        }
        self.objects = objects
        self.nextCursor = nextCursor
        self.truncated = truncated
        self.rawResponseByteCount = responseByteCount
        self.responseByteCount = accountedByteCount
    }
}

public enum CloudInventoryLimits {
    public static let maximumPageObjects = 500
    public static let maximumTotalObjects = 100_000
    public static let maximumCursorBytes = 16_384
    public static let maximumResponseBytes = 2_000_000
    public static let maximumTotalResponseBytes = 64_000_000
    public static let maximumElapsedSeconds: TimeInterval = 60
    public static let maximumRetryCount = 3
    public static let maximumConcurrentRequests = 2
}

public protocol CloudProviderAdapter: Sendable {
    var kind: CloudProviderKind { get }
    func connectionStatus(context: CloudRequestContext) async throws -> CloudConnectionStatus
    func accountReference(context: CloudRequestContext) async throws -> CloudConnectionReference
    func listPage(parentID: String?, cursor: String?, context: CloudRequestContext) async throws -> CloudInventoryPage
    func metadata(for objectID: String, context: CloudRequestContext) async throws -> CloudObjectReference
    func disconnect(context: CloudRequestContext) async throws
}

public enum CloudPathStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case full
    case homeRelative
    case redacted
}

public enum CloudMaterializationState: String, Codable, Hashable, Sendable {
    case local
    case placeholder
    case partiallyMaterialized
    case unknown
}

public enum ProtectReadinessNonClaims {
    public static let cloud = [
        "No local or remote file was deleted.",
        "No file was uploaded, moved, renamed, shared, or overwritten.",
        "Cloud metadata does not prove that a local file is safely backed up.",
        "Logical cloud bytes are not an immediate local disk reclaim estimate."
    ]

    public static let secrets = [
        "No secret value was migrated or copied.",
        "No source file was changed, quarantined, deleted, or added to version control.",
        "No 1Password vault item or field was inspected.",
        "Metadata-only discovery does not prove that a source contains a valid credential."
    ]
}
