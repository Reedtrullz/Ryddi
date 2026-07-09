import Foundation

public struct FilesystemIdentity: Codable, Hashable, Sendable {
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
        modificationDate: Date?
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
    }

    public static func capture(at url: URL) throws -> FilesystemIdentity {
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard let fileResourceIdentifier = stableIdentifier(values.fileResourceIdentifier),
              let volumeIdentifier = stableIdentifier(values.volumeIdentifier) else {
            throw FilesystemIdentityError.missingStableIdentifier(url.path)
        }
        return FilesystemIdentity(
            fileResourceIdentifier: fileResourceIdentifier,
            volumeIdentifier: volumeIdentifier,
            isDirectory: values.isDirectory ?? false,
            isRegularFile: values.isRegularFile ?? false,
            isSymbolicLink: values.isSymbolicLink ?? false,
            isPackage: values.isPackage ?? false,
            isVolume: values.isVolume ?? false,
            fileSize: values.fileSize.map(Int64.init),
            allocatedSize: (values.totalFileAllocatedSize ?? values.fileAllocatedSize).map(Int64.init),
            modificationDate: values.contentModificationDate
        )
    }

    public var digestComponent: String {
        [
            fileResourceIdentifier,
            volumeIdentifier,
            isDirectory ? "directory" : "not-directory",
            isRegularFile ? "regular" : "not-regular",
            isSymbolicLink ? "symlink" : "not-symlink",
            isPackage ? "package" : "not-package",
            isVolume ? "volume" : "not-volume",
            fileSize.map(String.init) ?? "no-size",
            allocatedSize.map(String.init) ?? "no-allocated-size",
            modificationDate.map { String($0.timeIntervalSince1970) } ?? "no-mtime"
        ].joined(separator: "\u{001f}")
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .contentModificationDateKey,
        .fileAllocatedSizeKey,
        .fileResourceIdentifierKey,
        .fileSizeKey,
        .isDirectoryKey,
        .isPackageKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isVolumeKey,
        .totalFileAllocatedSizeKey,
        .volumeIdentifierKey
    ]

    private static func stableIdentifier(_ value: Any?) -> String? {
        if let data = value as? Data {
            return "data:" + data.map { String(format: "%02x", $0) }.joined()
        }
        if let uuid = value as? UUID {
            return "uuid:" + uuid.uuidString.lowercased()
        }
        if let uuid = value as? NSUUID {
            return "uuid:" + uuid.uuidString.lowercased()
        }
        if let number = value as? NSNumber {
            return "number:" + number.stringValue
        }
        if let string = value as? String {
            return "string:" + string
        }
        return nil
    }
}

public enum FilesystemIdentityError: Error, LocalizedError, Equatable {
    case missingStableIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .missingStableIdentifier(let path):
            "Could not read stable filesystem identifiers for \(path)."
        }
    }
}
