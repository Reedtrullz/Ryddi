import Foundation

/// Provider-neutral filesystem evidence owned by Protect. It carries no mutation API.
public struct ProtectionFilesystemIdentity: Hashable, Sendable {
    public let fileResourceIdentifier: String
    public let volumeIdentifier: String
    public let isDirectory: Bool
    public let isRegularFile: Bool
    public let isSymbolicLink: Bool
    public let isPackage: Bool
    public let isVolume: Bool
    public let fileSize: Int64?
    public let allocatedSize: Int64?
    public let modificationDate: Date?
    public let hardLinkCount: Int?
    public let fileIdentityKey: String?

    public init(
        fileResourceIdentifier: String,
        volumeIdentifier: String,
        isDirectory: Bool,
        isRegularFile: Bool,
        isSymbolicLink: Bool,
        isPackage: Bool,
        isVolume: Bool,
        fileSize: Int64?,
        allocatedSize: Int64?,
        modificationDate: Date?,
        hardLinkCount: Int? = nil,
        fileIdentityKey: String? = nil
    ) {
        self.fileResourceIdentifier = fileResourceIdentifier
        self.volumeIdentifier = volumeIdentifier
        self.isDirectory = isDirectory
        self.isRegularFile = isRegularFile
        self.isSymbolicLink = isSymbolicLink
        self.isPackage = isPackage
        self.isVolume = isVolume
        self.fileSize = fileSize
        self.allocatedSize = allocatedSize
        self.modificationDate = modificationDate
        self.hardLinkCount = hardLinkCount
        self.fileIdentityKey = fileIdentityKey
    }
}

public enum ProtectionFileIdentityKind: String, Hashable, Sendable {
    case regularFile
    case directory
}

/// Descriptor-derived identity for metadata-only Protect inventory entries.
public struct ProtectionFileIdentity: Hashable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let kind: ProtectionFileIdentityKind
    public let standardizedPath: String

    public init(
        deviceID: UInt64,
        fileID: UInt64,
        kind: ProtectionFileIdentityKind,
        standardizedPath: String
    ) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.kind = kind
        self.standardizedPath = standardizedPath
    }
}
