import Foundation

public enum DownloadsReviewKind: String, Codable, CaseIterable, Hashable, Sendable {
    case diskImage
    case packageInstaller
    case archive
    case appBundle
    case other

    public var label: String {
        switch self {
        case .diskImage:
            return "Disk image"
        case .packageInstaller:
            return "Package installer"
        case .archive:
            return "Archive"
        case .appBundle:
            return "App bundle"
        case .other:
            return "Other"
        }
    }
}

public struct DownloadsReviewItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String
    public let kind: DownloadsReviewKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let modificationDate: Date?
    public let ageDays: Int?
    public let signals: [String]
    public let recommendation: String
    public let guidance: [String]

    public init(
        id: String = UUID().uuidString,
        path: String,
        displayName: String,
        kind: DownloadsReviewKind,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        modificationDate: Date? = nil,
        ageDays: Int? = nil,
        signals: [String],
        recommendation: String,
        guidance: [String]
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.kind = kind
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.modificationDate = modificationDate
        self.ageDays = ageDays
        self.signals = signals
        self.recommendation = recommendation
        self.guidance = guidance
    }
}

public struct DownloadsReviewKindSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: DownloadsReviewKind
    public let itemCount: Int
    public let allocatedSize: Int64

    public init(kind: DownloadsReviewKind, itemCount: Int, allocatedSize: Int64) {
        self.kind = kind
        self.itemCount = itemCount
        self.allocatedSize = allocatedSize
    }
}

public struct DownloadsReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let rootPath: String
    public let permissionState: PermissionState
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let itemCount: Int
    public let displayedItemCount: Int
    public let installerBytes: Int64
    public let archiveBytes: Int64
    public let oldCandidateBytes: Int64
    public let reviewCandidateBytes: Int64
    public let kindSummaries: [DownloadsReviewKindSummary]
    public let largestItems: [DownloadsReviewItem]
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
        installerBytes: Int64,
        archiveBytes: Int64,
        oldCandidateBytes: Int64,
        reviewCandidateBytes: Int64,
        kindSummaries: [DownloadsReviewKindSummary],
        largestItems: [DownloadsReviewItem],
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
        self.installerBytes = installerBytes
        self.archiveBytes = archiveBytes
        self.oldCandidateBytes = oldCandidateBytes
        self.reviewCandidateBytes = reviewCandidateBytes
        self.kindSummaries = kindSummaries
        self.largestItems = largestItems
        self.notes = notes
        self.guidance = guidance
        self.nonClaims = nonClaims
    }
}

public struct DownloadsReviewOptions: Hashable, Sendable {
    public let root: URL
    public let limit: Int
    public let oldDays: Int
    public let measurementDepth: Int
    public let includeHidden: Bool

    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
        limit: Int = 50,
        oldDays: Int = 90,
        measurementDepth: Int = 6,
        includeHidden: Bool = false
    ) {
        self.root = root.standardizedFileURL
        self.limit = max(1, min(limit, 500))
        self.oldDays = max(1, min(oldDays, 3650))
        self.measurementDepth = max(0, min(measurementDepth, 16))
        self.includeHidden = includeHidden
    }
}

public final class DownloadsReviewScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func review(
        options: DownloadsReviewOptions = DownloadsReviewOptions(),
        createdAt: Date = Date()
    ) -> DownloadsReviewReport {
        let root = options.root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .missing,
                note: "Downloads root does not exist at \(root.path)."
            )
        }

        guard isDirectory.boolValue else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .unknown,
                note: "Configured Downloads root is not a directory: \(root.path)."
            )
        }

        guard fileManager.isReadableFile(atPath: root.path) else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .denied,
                note: "Downloads root is not readable with current permissions: \(root.path)."
            )
        }

        var listingOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden {
            listingOptions.insert(.skipsHiddenFiles)
        }
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: downloadsResourceKeys,
            options: listingOptions
        ) else {
            return emptyReport(
                root: root,
                createdAt: createdAt,
                permissionState: .denied,
                note: "Could not list Downloads contents at \(root.path)."
            )
        }

        let items = children.map {
            item(
                for: $0,
                root: root,
                oldDays: options.oldDays,
                measurementDepth: options.measurementDepth,
                referenceDate: createdAt
            )
        }
            .sorted { lhs, rhs in
                if lhs.allocatedSize == rhs.allocatedSize {
                    return lhs.path < rhs.path
                }
                return lhs.allocatedSize > rhs.allocatedSize
            }

        let logical = items.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let measuredCount = items.reduce(0) { $0 + max(1, $1.itemCount) }
        let installerKinds: Set<DownloadsReviewKind> = [.diskImage, .packageInstaller, .appBundle]
        let installerBytes = items
            .filter { installerKinds.contains($0.kind) }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let archiveBytes = items
            .filter { $0.kind == .archive }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let oldBytes = items
            .filter { ($0.ageDays ?? 0) >= options.oldDays }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let reviewBytes = items
            .filter { item in
                item.kind != .other || (item.ageDays ?? 0) >= options.oldDays
            }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        let summaries = DownloadsReviewKind.allCases.compactMap { kind -> DownloadsReviewKindSummary? in
            let matches = items.filter { $0.kind == kind }
            guard !matches.isEmpty else { return nil }
            return DownloadsReviewKindSummary(
                kind: kind,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
        let notes = [
            "Measured immediate entries under \(root.path).",
            "Old-download threshold: \(options.oldDays) day(s).",
            options.includeHidden ? "Hidden entries were included." : "Hidden entries were skipped; pass --include-hidden to review them."
        ]

        return DownloadsReviewReport(
            createdAt: createdAt,
            rootPath: root.path,
            permissionState: .readable,
            totalLogicalSize: logical,
            totalAllocatedSize: allocated,
            itemCount: measuredCount,
            displayedItemCount: min(items.count, options.limit),
            installerBytes: installerBytes,
            archiveBytes: archiveBytes,
            oldCandidateBytes: oldBytes,
            reviewCandidateBytes: reviewBytes,
            kindSummaries: summaries,
            largestItems: Array(items.prefix(options.limit)),
            notes: notes,
            guidance: Self.guidance(rootPath: root.path),
            nonClaims: Self.nonClaims
        )
    }

    private func emptyReport(
        root: URL,
        createdAt: Date,
        permissionState: PermissionState,
        note: String
    ) -> DownloadsReviewReport {
        DownloadsReviewReport(
            createdAt: createdAt,
            rootPath: root.path,
            permissionState: permissionState,
            totalLogicalSize: 0,
            totalAllocatedSize: 0,
            itemCount: 0,
            displayedItemCount: 0,
            installerBytes: 0,
            archiveBytes: 0,
            oldCandidateBytes: 0,
            reviewCandidateBytes: 0,
            kindSummaries: [],
            largestItems: [],
            notes: [note],
            guidance: Self.guidance(rootPath: root.path),
            nonClaims: Self.nonClaims
        )
    }

    private func item(
        for url: URL,
        root: URL,
        oldDays: Int,
        measurementDepth: Int,
        referenceDate: Date
    ) -> DownloadsReviewItem {
        let values = try? url.resourceValues(forKeys: Set(downloadsResourceKeys))
        let measurement = measure(url: url, maxDepth: measurementDepth)
        let kind = Self.kind(for: url, isDirectory: values?.isDirectory ?? false)
        let modified = values?.contentModificationDate
        let ageDays = modified.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: referenceDate).day ?? 0) }
        let isOld = (ageDays ?? 0) >= oldDays
        let signals = Self.signals(kind: kind, isOld: isOld, isSymbolicLink: values?.isSymbolicLink == true)
        return DownloadsReviewItem(
            path: url.path,
            displayName: url.lastPathComponent,
            kind: kind,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            itemCount: measurement.itemCount,
            isDirectory: values?.isDirectory ?? false,
            isSymbolicLink: values?.isSymbolicLink ?? false,
            modificationDate: modified,
            ageDays: ageDays,
            signals: signals,
            recommendation: Self.recommendation(kind: kind, isOld: isOld),
            guidance: Self.itemGuidance(kind: kind, isOld: isOld, isSymbolicLink: values?.isSymbolicLink == true)
        )
    }

    private func measure(url: URL, maxDepth: Int) -> DownloadsMeasurement {
        guard let values = try? url.resourceValues(forKeys: Set(downloadsResourceKeys)) else {
            return DownloadsMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        if values.isSymbolicLink == true {
            return DownloadsMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return DownloadsMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }
        guard maxDepth > 0 else {
            return DownloadsMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: downloadsResourceKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return DownloadsMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        for case let child as URL in enumerator {
            let depth = max(0, child.pathComponents.count - url.pathComponents.count)
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(downloadsResourceKeys)) else { continue }
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
        return DownloadsMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }

    private static func kind(for url: URL, isDirectory: Bool) -> DownloadsReviewKind {
        let ext = url.pathExtension.lowercased()
        if isDirectory, ext == "app" {
            return .appBundle
        }
        if ["dmg", "iso", "cdr", "sparseimage", "sparsebundle"].contains(ext) {
            return .diskImage
        }
        if ["pkg", "mpkg"].contains(ext) {
            return .packageInstaller
        }
        if ["zip", "xip", "rar", "7z", "tar", "tgz", "tbz", "tbz2", "txz", "gz", "bz2", "xz"].contains(ext) {
            return .archive
        }
        return .other
    }

    private static func signals(kind: DownloadsReviewKind, isOld: Bool, isSymbolicLink: Bool) -> [String] {
        var result: [String] = []
        switch kind {
        case .diskImage, .packageInstaller, .appBundle:
            result.append("installer")
        case .archive:
            result.append("archive")
        case .other:
            break
        }
        if isOld {
            result.append("old-download")
        }
        if isSymbolicLink {
            result.append("symlink-not-followed")
        }
        return result
    }

    private static func recommendation(kind: DownloadsReviewKind, isOld: Bool) -> String {
        switch (kind, isOld) {
        case (.diskImage, true), (.packageInstaller, true), (.appBundle, true):
            return "Review for Trash after confirming the app or package is already installed."
        case (.diskImage, false), (.packageInstaller, false), (.appBundle, false):
            return "Keep until you confirm installation or no longer need the installer."
        case (.archive, true):
            return "Review for Trash or archive after confirming the contents were extracted or backed up."
        case (.archive, false):
            return "Keep until you confirm the archive contents are no longer needed."
        case (.other, true):
            return "Manual review; archive, move, or Trash from Finder if it is no longer needed."
        case (.other, false):
            return "No cleanup recommendation; review manually if space pressure is high."
        }
    }

    private static func itemGuidance(kind: DownloadsReviewKind, isOld: Bool, isSymbolicLink: Bool) -> [String] {
        var guidance: [String]
        switch kind {
        case .diskImage, .packageInstaller, .appBundle:
            guidance = ["Confirm the software is installed and working before removing this installer."]
        case .archive:
            guidance = ["Confirm the archive has been extracted or backed up before removing it."]
        case .other:
            guidance = ["Open in Finder and confirm whether this is still useful."]
        }
        if isOld {
            guidance.append("Age is a review signal only; old does not mean safe to delete.")
        }
        if isSymbolicLink {
            guidance.append("Symbolic link was not followed while measuring.")
        }
        return guidance
    }

    private static func guidance(rootPath: String) -> [String] {
        [
            "Review \(rootPath) in Finder before removing old downloads.",
            "Installed apps, extracted archives, and copied documents can make old installers removable, but Ryddi cannot prove that for you.",
            "Use Trash or manual archive workflows for Downloads in this version; Ryddi does not automatically delete Downloads entries."
        ]
    }

    public static let nonClaims = [
        "Downloads Review is report-only; it does not delete, move, archive, compress, or Trash files.",
        "Installer and archive classification is extension-based and cannot prove whether the contents are installed, extracted, backed up, or still needed.",
        "Old-download age is only a review signal and does not make a file safe to remove.",
        "Downloads size is not promised immediate free-space recovery because APFS snapshots, purgeable storage, and concurrent system activity can affect accounting."
    ]
}

private struct DownloadsMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private let downloadsResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]
