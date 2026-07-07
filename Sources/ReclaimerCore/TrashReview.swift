import Foundation

public struct TrashReviewItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let modificationDate: Date?
    public let guidance: [String]

    public init(
        id: String = UUID().uuidString,
        path: String,
        displayName: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        modificationDate: Date? = nil,
        guidance: [String]
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.modificationDate = modificationDate
        self.guidance = guidance
    }
}

public extension TrashReviewItem {
    var nextAction: ReviewNextAction {
        .reviewInFinder
    }
}

public struct TrashReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let rootPath: String
    public let permissionState: PermissionState
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let itemCount: Int
    public let displayedItemCount: Int
    public let largestItems: [TrashReviewItem]
    public let notes: [String]
    public let guidance: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        rootPath: String,
        permissionState: PermissionState,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        itemCount: Int,
        displayedItemCount: Int,
        largestItems: [TrashReviewItem],
        notes: [String],
        guidance: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rootPath = rootPath
        self.permissionState = permissionState
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.itemCount = itemCount
        self.displayedItemCount = displayedItemCount
        self.largestItems = largestItems
        self.notes = notes
        self.guidance = guidance
        self.nonClaims = nonClaims
    }
}

public struct TrashReviewOptions: Hashable, Sendable {
    public let root: URL
    public let limit: Int
    public let measurementDepth: Int

    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"),
        limit: Int = 30,
        measurementDepth: Int = 8
    ) {
        self.root = root.standardizedFileURL
        self.limit = max(1, min(limit, 500))
        self.measurementDepth = max(0, min(measurementDepth, 16))
    }
}

public final class TrashReviewScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func review(
        options: TrashReviewOptions = TrashReviewOptions(),
        createdAt: Date = Date()
    ) -> TrashReviewReport {
        let root = options.root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return TrashReviewReport(
                createdAt: createdAt,
                rootPath: root.path,
                permissionState: .missing,
                totalLogicalSize: 0,
                totalAllocatedSize: 0,
                itemCount: 0,
                displayedItemCount: 0,
                largestItems: [],
                notes: ["Trash root does not exist at \(root.path)."],
                guidance: Self.guidance(rootPath: root.path),
                nonClaims: Self.nonClaims
            )
        }

        guard isDirectory.boolValue else {
            return TrashReviewReport(
                createdAt: createdAt,
                rootPath: root.path,
                permissionState: .unknown,
                totalLogicalSize: 0,
                totalAllocatedSize: 0,
                itemCount: 0,
                displayedItemCount: 0,
                largestItems: [],
                notes: ["Configured Trash root is not a directory: \(root.path)."],
                guidance: Self.guidance(rootPath: root.path),
                nonClaims: Self.nonClaims
            )
        }

        guard fileManager.isReadableFile(atPath: root.path) else {
            return TrashReviewReport(
                createdAt: createdAt,
                rootPath: root.path,
                permissionState: .denied,
                totalLogicalSize: 0,
                totalAllocatedSize: 0,
                itemCount: 0,
                displayedItemCount: 0,
                largestItems: [],
                notes: ["Trash root is not readable with current permissions: \(root.path)."],
                guidance: Self.guidance(rootPath: root.path),
                nonClaims: Self.nonClaims
            )
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: trashResourceKeys,
            options: []
        ) else {
            return TrashReviewReport(
                createdAt: createdAt,
                rootPath: root.path,
                permissionState: .denied,
                totalLogicalSize: 0,
                totalAllocatedSize: 0,
                itemCount: 0,
                displayedItemCount: 0,
                largestItems: [],
                notes: ["Could not list Trash contents at \(root.path)."],
                guidance: Self.guidance(rootPath: root.path),
                nonClaims: Self.nonClaims
            )
        }

        let items = children.map { item(for: $0, measurementDepth: options.measurementDepth) }
            .sorted { lhs, rhs in
                if lhs.allocatedSize == rhs.allocatedSize {
                    return lhs.path < rhs.path
                }
                return lhs.allocatedSize > rhs.allocatedSize
            }
        let logical = items.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let count = items.reduce(0) { $0 + max(1, $1.itemCount) }
        let notes = [
            "Measured immediate Trash entries under \(root.path).",
            "Use Finder Trash to inspect, restore, or empty items manually."
        ]

        return TrashReviewReport(
            createdAt: createdAt,
            rootPath: root.path,
            permissionState: .readable,
            totalLogicalSize: logical,
            totalAllocatedSize: allocated,
            itemCount: count,
            displayedItemCount: min(items.count, options.limit),
            largestItems: Array(items.prefix(options.limit)),
            notes: notes,
            guidance: Self.guidance(rootPath: root.path),
            nonClaims: Self.nonClaims
        )
    }

    private func item(for url: URL, measurementDepth: Int) -> TrashReviewItem {
        let values = try? url.resourceValues(forKeys: Set(trashResourceKeys))
        let measurement = measure(url: url, maxDepth: measurementDepth)
        let isDirectory = values?.isDirectory ?? false
        let isSymbolicLink = values?.isSymbolicLink ?? false
        var guidance = [
            "Open in Finder Trash before deciding whether to restore or empty this item.",
            "Confirm this is not the only copy before emptying Trash."
        ]
        if isSymbolicLink {
            guidance.append("Symbolic link was not followed while measuring.")
        }
        return TrashReviewItem(
            path: url.path,
            displayName: url.lastPathComponent,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            itemCount: measurement.itemCount,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            modificationDate: values?.contentModificationDate,
            guidance: guidance
        )
    }

    private func measure(url: URL, maxDepth: Int) -> TrashMeasurement {
        guard maxDepth >= 0 else {
            return TrashMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        guard let values = try? url.resourceValues(forKeys: Set(trashResourceKeys)) else {
            return TrashMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        if values.isSymbolicLink == true {
            return TrashMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return TrashMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }
        guard maxDepth > 0 else {
            return TrashMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: trashResourceKeys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return TrashMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        for case let child as URL in enumerator {
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(trashResourceKeys)) else { continue }
            if childValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if childValues.isDirectory == true {
                continue
            }
            logical += Int64(childValues.fileSize ?? 0)
            allocated += Int64(childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return TrashMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }

    private static func guidance(rootPath: String) -> [String] {
        [
            "Review Finder Trash for \(rootPath) before emptying anything.",
            "Restore items from Finder Trash when you are unsure whether they are the only copy.",
            "Emptying Trash is a Finder/macOS action in this version of Ryddi, not an unattended cleanup."
        ]
    }

    public static let nonClaims = [
        "Trash Review is report-only; it does not empty Trash, restore items, move files, or delete files.",
        "Ryddi cannot prove Finder Trash still contains an item after this report is generated.",
        "Trash size is not promised immediate free-space recovery because APFS snapshots, purgeable storage, external volumes, and concurrent system activity can affect accounting.",
        "This report reviews the configured user Trash root only; external-volume Trash locations may need separate Finder review."
    ]
}

private struct TrashMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private let trashResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]
