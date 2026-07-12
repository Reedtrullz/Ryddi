import Foundation

#if canImport(Darwin)
import Darwin
#endif

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

    public static func capture(at url: URL) throws -> FilesystemIdentity {
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard let fileResourceIdentifier = stableIdentifier(values.fileResourceIdentifier),
              let volumeIdentifier = stableIdentifier(values.volumeIdentifier) else {
            throw FilesystemIdentityError.missingStableIdentifier(url.path)
        }
        let linkMetadata = linkMetadata(at: url)
        let isSymbolicLink = linkMetadata?.isSymbolicLink ?? values.isSymbolicLink ?? false
        let isRegularFile = linkMetadata?.isRegularFile ?? values.isRegularFile ?? false
        let isDirectory = linkMetadata?.isDirectory ?? values.isDirectory ?? false
        let linkIdentity = isRegularFile && !isSymbolicLink ? linkMetadata : nil

        return FilesystemIdentity(
            fileResourceIdentifier: fileResourceIdentifier,
            volumeIdentifier: volumeIdentifier,
            isDirectory: isDirectory,
            isRegularFile: isRegularFile,
            isSymbolicLink: isSymbolicLink,
            isPackage: values.isPackage ?? false,
            isVolume: values.isVolume ?? false,
            fileSize: values.fileSize.map(Int64.init),
            allocatedSize: (values.totalFileAllocatedSize ?? values.fileAllocatedSize).map(Int64.init),
            modificationDate: values.contentModificationDate,
            hardLinkCount: linkIdentity?.hardLinkCount,
            fileIdentityKey: linkIdentity.map { "volume:\(volumeIdentifier)|device:\($0.device)|inode:\($0.inode)" }
        )
    }

    public var digestComponent: String {
        var components = [
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
        ]
        if let hardLinkCount {
            components.append("hard-link-count:\(hardLinkCount)")
        }
        if let fileIdentityKey {
            components.append("file-identity-key:\(fileIdentityKey)")
        }
        return components.joined(separator: "\u{001f}")
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

    private struct LinkMetadata {
        let isDirectory: Bool
        let isRegularFile: Bool
        let isSymbolicLink: Bool
        let hardLinkCount: Int?
        let device: String
        let inode: String
    }

    private static func linkMetadata(at url: URL) -> LinkMetadata? {
        #if canImport(Darwin)
        return url.withUnsafeFileSystemRepresentation { representation in
            guard let representation else { return nil }
            var info = Darwin.stat()
            guard Darwin.lstat(representation, &info) == 0 else {
                return nil
            }

            let mode = info.st_mode
            let fileType = mode & S_IFMT
            let isDirectory = fileType == S_IFDIR
            let isRegularFile = fileType == S_IFREG
            let isSymbolicLink = fileType == S_IFLNK
            return LinkMetadata(
                isDirectory: isDirectory,
                isRegularFile: isRegularFile,
                isSymbolicLink: isSymbolicLink,
                hardLinkCount: isRegularFile ? Int(info.st_nlink) : nil,
                device: String(describing: info.st_dev),
                inode: String(describing: info.st_ino)
            )
        }
        #else
        return nil
        #endif
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
