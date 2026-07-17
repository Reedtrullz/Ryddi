import Foundation

public enum GuidedMapStoreError: Error, Equatable, Sendable {
    case unsafeRoot
    case unsafeFile(String)
    case oversizedFile(String)
    case unsupportedSchema(Int)
}

public final class GuidedMapStore: @unchecked Sendable {
    public static let maximumFileBytes: Int64 = 8 * 1024 * 1024

    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL? = nil, fileManager: FileManager = .default) {
        self.root = (root ?? Self.defaultRoot()).standardizedFileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_GUIDED_MAP_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ryddi/GuidedMaps", isDirectory: true)
    }

    @discardableResult
    public func save(_ snapshot: GuidedMapSnapshot) throws -> URL {
        guard snapshot.schemaVersion == GuidedMapSnapshot.currentSchemaVersion else {
            throw GuidedMapStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        try prepareRoot()
        let safeID = snapshot.scanID.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "-",
            options: .regularExpression
        )
        let filename = "guided-map-\(timestamp(snapshot.capturedAt))-\(safeID).json"
        let url = root.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
        guard url.deletingLastPathComponent() == root else {
            throw GuidedMapStoreError.unsafeFile(filename)
        }
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumFileBytes else {
            throw GuidedMapStoreError.oversizedFile(filename)
        }
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    public func latest() -> GuidedMapSnapshot? {
        validSnapshots()
            .sorted {
                if $0.snapshot.capturedAt == $1.snapshot.capturedAt {
                    return $0.url.lastPathComponent > $1.url.lastPathComponent
                }
                return $0.snapshot.capturedAt > $1.snapshot.capturedAt
            }
            .first?
            .snapshot
    }

    public func recent(limit: Int = 12) -> [GuidedMapSnapshot] {
        Array(validSnapshots()
            .sorted {
                if $0.snapshot.capturedAt == $1.snapshot.capturedAt {
                    return $0.url.lastPathComponent > $1.url.lastPathComponent
                }
                return $0.snapshot.capturedAt > $1.snapshot.capturedAt
            }
            .prefix(max(0, limit))
            .map(\.snapshot))
    }

    private func prepareRoot() throws {
        if fileManager.fileExists(atPath: root.path) {
            let values = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw GuidedMapStoreError.unsafeRoot
            }
        } else {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    private func validSnapshots() -> [(url: URL, snapshot: GuidedMapSnapshot)] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ) else {
            return []
        }
        return files.compactMap { url in
            let standardized = url.standardizedFileURL
            guard standardized.deletingLastPathComponent() == root,
                  standardized.lastPathComponent.hasPrefix("guided-map-"),
                  standardized.pathExtension == "json",
                  let values = try? standardized.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                  ),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  Int64(values.fileSize ?? 0) <= Self.maximumFileBytes,
                  let data = try? Data(contentsOf: standardized, options: [.mappedIfSafe]),
                  let snapshot = try? decoder.decode(GuidedMapSnapshot.self, from: data),
                  snapshot.schemaVersion == GuidedMapSnapshot.currentSchemaVersion else {
                return nil
            }
            return (standardized, snapshot)
        }
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
