import Foundation

public struct HeldItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let originalPath: String?
    public let heldPath: String
    public let displayName: String
    public let heldAt: Date?
    public let allocatedSize: Int64
    public let isDirectory: Bool

    public init(
        id: String,
        originalPath: String?,
        heldPath: String,
        displayName: String,
        heldAt: Date?,
        allocatedSize: Int64,
        isDirectory: Bool
    ) {
        self.id = id
        self.originalPath = originalPath
        self.heldPath = heldPath
        self.displayName = displayName
        self.heldAt = heldAt
        self.allocatedSize = allocatedSize
        self.isDirectory = isDirectory
    }
}

struct HoldingMetadata: Codable, Hashable, Sendable {
    let originalPath: String
    let heldAt: Date
    let allocatedSize: Int64
    let isDirectory: Bool
}

public final class HoldingStore: @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let metadataName = ".reclaimer-hold.json"

    public init(
        root: URL = ExecutorConfiguration().holdingRoot,
        fileManager: FileManager = .default
    ) {
        self.root = root
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func recordHold(source: URL, target: URL, finding: Finding) throws {
        let metadata = HoldingMetadata(
            originalPath: source.path,
            heldAt: Date(),
            allocatedSize: finding.allocatedSize,
            isDirectory: finding.isDirectory
        )
        let metadataURL = target.deletingLastPathComponent().appendingPathComponent(metadataName)
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    public func list() -> [HeldItem] {
        guard let holdDirectories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return holdDirectories
            .compactMap(heldItem(in:))
            .sorted { lhs, rhs in
                (lhs.heldAt ?? .distantPast) > (rhs.heldAt ?? .distantPast)
            }
    }

    public func restore(id: String, to explicitDestination: URL? = nil) throws -> URL {
        guard let item = list().first(where: { $0.id == id }) else {
            throw error("No held item found for id \(id).")
        }
        let heldURL = URL(fileURLWithPath: item.heldPath)
        guard isInsideRoot(heldURL) else {
            throw error("Held item is outside the holding root.")
        }

        let destination = explicitDestination ?? {
            if let originalPath = item.originalPath {
                return URL(fileURLWithPath: originalPath)
            }
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Restored Ryddi Items", isDirectory: true)
                .appendingPathComponent(item.displayName)
        }()

        guard !fileManager.fileExists(atPath: destination.path) else {
            throw error("Destination already exists: \(destination.path)")
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: heldURL, to: destination)
        try removeEmptyHoldDirectory(containing: heldURL)
        return destination
    }

    @discardableResult
    public func expire(olderThan cutoff: Date, dryRun: Bool = true) throws -> [HeldItem] {
        let expired = list().filter { item in
            guard let heldAt = item.heldAt else { return false }
            return heldAt < cutoff
        }
        guard !dryRun else {
            return expired
        }

        for item in expired {
            let heldURL = URL(fileURLWithPath: item.heldPath)
            guard isInsideRoot(heldURL) else { continue }
            let holdDirectory = heldURL.deletingLastPathComponent()
            if isInsideRoot(holdDirectory) {
                try fileManager.removeItem(at: holdDirectory)
            }
        }
        return expired
    }

    private func heldItem(in holdDirectory: URL) -> HeldItem? {
        guard isInsideRoot(holdDirectory) else { return nil }
        guard (try? holdDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return nil
        }
        guard let children = try? fileManager.contentsOfDirectory(
            at: holdDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else {
            return nil
        }

        let heldURL = children.first { $0.lastPathComponent != metadataName }
        guard let heldURL else { return nil }
        let metadata = readMetadata(in: holdDirectory)
        let values = try? heldURL.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        let allocated = metadata?.allocatedSize
            ?? Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        let id = holdDirectory.lastPathComponent + "/" + heldURL.lastPathComponent
        return HeldItem(
            id: id,
            originalPath: metadata?.originalPath,
            heldPath: heldURL.path,
            displayName: heldURL.lastPathComponent,
            heldAt: metadata?.heldAt ?? ((try? holdDirectory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate),
            allocatedSize: allocated,
            isDirectory: metadata?.isDirectory ?? (values?.isDirectory ?? false)
        )
    }

    private func readMetadata(in holdDirectory: URL) -> HoldingMetadata? {
        let metadataURL = holdDirectory.appendingPathComponent(metadataName)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? decoder.decode(HoldingMetadata.self, from: data)
    }

    private func removeEmptyHoldDirectory(containing heldURL: URL) throws {
        let holdDirectory = heldURL.deletingLastPathComponent()
        guard isInsideRoot(holdDirectory) else { return }
        let remaining = (try? fileManager.contentsOfDirectory(atPath: holdDirectory.path)) ?? []
        if remaining.allSatisfy({ $0 == metadataName }) {
            try fileManager.removeItem(at: holdDirectory)
        }
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "Ryddi.HoldingStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
