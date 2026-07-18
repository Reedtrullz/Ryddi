import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum CloudRootConfirmationError: Error, Hashable, LocalizedError, Sendable {
    case unsafeBroadRoot
    case symbolicLink
    case notDirectory
    case identityChanged

    public var errorDescription: String? {
        switch self {
        case .unsafeBroadRoot: "Choose the cloud sync folder itself, not a filesystem or home-directory root."
        case .symbolicLink: "Cloud sync roots cannot be symbolic links."
        case .notDirectory: "The selected cloud sync root is no longer an accessible directory."
        case .identityChanged: "The cloud sync root changed since discovery. Discover it again before confirming."
        }
    }
}

public struct CloudConfirmedStorageRoot: Identifiable, Sendable {
    public let id: String
    public let candidate: CloudStorageRootCandidate
    public let confirmedAt: Date

    fileprivate init(candidate: CloudStorageRootCandidate, confirmedAt: Date) {
        self.id = candidate.id
        self.candidate = candidate
        self.confirmedAt = confirmedAt
    }
}

public enum CloudStorageRootConfirmation {
    public static func confirm(
        _ candidate: CloudStorageRootCandidate,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) throws -> CloudConfirmedStorageRoot {
        let root = candidate.url.standardizedFileURL
        let home = home.standardizedFileURL
        let isHomeAncestor = home.path.hasPrefix(root.path.hasSuffix("/") ? root.path : "\(root.path)/")
        let cloudContainer = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .standardizedFileURL
        let isCloudContainerAncestor = cloudContainer.path == root.path
            || cloudContainer.path.hasPrefix(root.path.hasSuffix("/") ? root.path : "\(root.path)/")
        let volumeRoot = try? root.resourceValues(forKeys: [.volumeURLKey]).volume
        let isVolumeRoot = volumeRoot?.standardizedFileURL.path == root.path
        guard root.pathComponents.count > 2,
              root.path != home.path,
              !isHomeAncestor,
              !isCloudContainerAncestor,
              !isVolumeRoot else {
            throw CloudRootConfirmationError.unsafeBroadRoot
        }
        guard let metadata = CloudLocalMetadata.read(root) else {
            throw CloudRootConfirmationError.notDirectory
        }
        guard metadata.kind != .symbolicLink else {
            throw CloudRootConfirmationError.symbolicLink
        }
        guard metadata.kind == .directory else {
            throw CloudRootConfirmationError.notDirectory
        }
        guard metadata.identity == candidate.identity else {
            throw CloudRootConfirmationError.identityChanged
        }
        return CloudConfirmedStorageRoot(candidate: candidate, confirmedAt: now)
    }
}

public struct CloudLocalInventoryOptions: Hashable, Sendable {
    public let maximumEntries: Int
    public let maximumDirectories: Int
    public let maximumDepth: Int
    public let maximumDuration: TimeInterval
    public let reviewLimit: Int
    public let staleAge: TimeInterval

    public init(
        maximumEntries: Int = 25_000,
        maximumDirectories: Int = 5_000,
        maximumDepth: Int = 12,
        maximumDuration: TimeInterval = 10,
        reviewLimit: Int = 50,
        staleAge: TimeInterval = 365 * 24 * 60 * 60
    ) {
        self.maximumEntries = max(1, maximumEntries)
        self.maximumDirectories = max(1, maximumDirectories)
        self.maximumDepth = max(0, maximumDepth)
        self.maximumDuration = maximumDuration.isFinite ? max(0, maximumDuration) : 10
        self.reviewLimit = min(200, max(1, reviewLimit))
        self.staleAge = staleAge.isFinite ? max(1, staleAge) : 365 * 24 * 60 * 60
    }
}

public enum CloudLocalInventoryIssue: String, Hashable, Sendable {
    case cancelled
    case depthLimitReached
    case directoryLimitReached
    case entryLimitReached
    case rootIdentityChanged
    case rootUnavailable
    case timeLimitReached
    case unreadableEntries

    public var label: String {
        switch self {
        case .cancelled: "Inventory was cancelled."
        case .depthLimitReached: "Some folders exceeded the depth limit."
        case .directoryLimitReached: "The directory limit was reached."
        case .entryLimitReached: "The file and folder entry limit was reached."
        case .rootIdentityChanged: "The confirmed root changed during inventory; results were discarded."
        case .rootUnavailable: "The confirmed root is unavailable or no longer a directory."
        case .timeLimitReached: "The inventory time limit was reached."
        case .unreadableEntries: "Some folders or entries could not be read."
        }
    }
}

public struct CloudLocalFileReview: Hashable, Identifiable, Sendable {
    public let id: String
    public let relativePath: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let modifiedAt: Date

    public var hasNoAllocatedBlocks: Bool {
        logicalBytes > 0 && allocatedBytes == 0
    }
}

public struct CloudLocalInventoryReport: Sendable {
    public let root: CloudConfirmedStorageRoot
    public let generatedAt: Date
    public let scannedEntryCount: Int
    public let directoryCount: Int
    public let fileCount: Int
    public let skippedSymbolicLinkCount: Int
    public let unreadableEntryCount: Int
    public let zeroAllocatedBlockFileCount: Int
    public let sharedFileIdentityCount: Int
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let largeFiles: [CloudLocalFileReview]
    public let staleFiles: [CloudLocalFileReview]
    public let issues: [CloudLocalInventoryIssue]
    public let nonClaims: [String]

    public var isComplete: Bool { issues.isEmpty }
    public var resultsAreTrusted: Bool {
        !issues.contains(.rootIdentityChanged) && !issues.contains(.rootUnavailable)
    }

    public func absoluteURL(for item: CloudLocalFileReview) -> URL {
        root.candidate.url.appendingPathComponent(item.relativePath)
    }
}

public struct CloudLocalInventoryScanner: Sendable {
    public static let nonClaims = [
        "Inventory reads names and filesystem metadata only; it never opens file contents or requests placeholder hydration.",
        "Zero allocated blocks can indicate an online-only placeholder or a sparse file; Ryddi does not claim which without provider evidence.",
        "Logical cloud bytes are not the same as locally reclaimable APFS bytes.",
        "Allocated bytes deduplicate hard links but can still include APFS clone-shared blocks; they are a local footprint estimate, not unique physical usage.",
        "Local metadata cannot prove that a file is uploaded, current, versioned, remotely recoverable, or duplicated.",
        "Inventory never moves, renames, uploads, downloads, deduplicates, or deletes files."
    ]

    public init() {}

    public func scan(
        root: CloudConfirmedStorageRoot,
        options: CloudLocalInventoryOptions = CloudLocalInventoryOptions(),
        now: Date = Date()
    ) -> CloudLocalInventoryReport {
        let started = DispatchTime.now().uptimeNanoseconds
        let durationNanos = UInt64(min(options.maximumDuration, 86_400) * 1_000_000_000)
        let deadline = started.addingReportingOverflow(durationNanos)
        let deadlineNanos = deadline.overflow ? UInt64.max : deadline.partialValue
        let cutoff = now.addingTimeInterval(-options.staleAge)
        var issues = Set<CloudLocalInventoryIssue>()
        var queue: [(url: URL, relativePath: String, depth: Int)] = [
            (root.candidate.url, "", 0)
        ]
        var queueIndex = 0
        var scannedEntries = 0
        var directoryCount = 0
        var fileCount = 0
        var skippedSymlinks = 0
        var unreadableEntries = 0
        var zeroAllocatedBlocks = 0
        var sharedFileIdentities = 0
        var seenRegularFileIdentities = Set<CloudRootIdentity>()
        var logicalBytes: Int64 = 0
        var allocatedBytes: Int64 = 0
        var largeFiles: [CloudLocalFileReview] = []
        var staleFiles: [CloudLocalFileReview] = []

        guard Self.matchesConfirmedRoot(root) else {
            return emptyReport(root: root, now: now, issue: .rootUnavailable)
        }

        scanLoop: while queueIndex < queue.count {
            if Task.isCancelled {
                issues.insert(.cancelled)
                break
            }
            if DispatchTime.now().uptimeNanoseconds >= deadlineNanos {
                issues.insert(.timeLimitReached)
                break
            }
            guard directoryCount < options.maximumDirectories else {
                issues.insert(.directoryLimitReached)
                break
            }

            let directory = queue[queueIndex]
            queueIndex += 1
            guard let directoryMetadata = CloudLocalMetadata.read(directory.url) else {
                unreadableEntries += 1
                issues.insert(.unreadableEntries)
                continue
            }
            if directoryMetadata.kind == .symbolicLink {
                skippedSymlinks += 1
                continue
            }
            guard directoryMetadata.kind == .directory else {
                unreadableEntries += 1
                issues.insert(.unreadableEntries)
                continue
            }
            directoryCount += 1

            let directoryRead: CloudLocalDirectoryRead
            do {
                directoryRead = try CloudLocalDirectoryReader.read(
                    directory.url,
                    limit: options.maximumEntries - scannedEntries,
                    deadlineNanos: deadlineNanos
                )
            } catch {
                unreadableEntries += 1
                issues.insert(.unreadableEntries)
                continue
            }
            if directoryRead.invalidNameCount > 0 {
                scannedEntries += directoryRead.invalidNameCount
                unreadableEntries += directoryRead.invalidNameCount
                issues.insert(.unreadableEntries)
            }

            for name in directoryRead.names {
                if Task.isCancelled {
                    issues.insert(.cancelled)
                    break scanLoop
                }
                if DispatchTime.now().uptimeNanoseconds >= deadlineNanos {
                    issues.insert(.timeLimitReached)
                    break scanLoop
                }
                guard scannedEntries < options.maximumEntries else {
                    issues.insert(.entryLimitReached)
                    break scanLoop
                }
                scannedEntries += 1

                let childURL = directory.url.appendingPathComponent(name)
                let relativePath = directory.relativePath.isEmpty ? name : "\(directory.relativePath)/\(name)"
                guard let metadata = CloudLocalMetadata.read(childURL) else {
                    unreadableEntries += 1
                    issues.insert(.unreadableEntries)
                    continue
                }
                switch metadata.kind {
                case .symbolicLink:
                    skippedSymlinks += 1
                case .directory:
                    if directory.depth < options.maximumDepth {
                        queue.append((childURL, relativePath, directory.depth + 1))
                    } else {
                        issues.insert(.depthLimitReached)
                    }
                case .regularFile:
                    fileCount += 1
                    logicalBytes = Self.saturatingAdd(logicalBytes, metadata.logicalBytes)
                    if metadata.logicalBytes > 0 && metadata.allocatedBytes == 0 {
                        zeroAllocatedBlocks += 1
                    }
                    guard seenRegularFileIdentities.insert(metadata.identity).inserted else {
                        sharedFileIdentities += 1
                        continue
                    }
                    allocatedBytes = Self.saturatingAdd(allocatedBytes, metadata.allocatedBytes)
                    let item = CloudLocalFileReview(
                        id: "\(metadata.identity.deviceID):\(metadata.identity.inode):\(relativePath)",
                        relativePath: relativePath,
                        logicalBytes: metadata.logicalBytes,
                        allocatedBytes: metadata.allocatedBytes,
                        modifiedAt: metadata.modifiedAt
                    )
                    if metadata.allocatedBytes > 0 {
                        Self.retain(item, in: &largeFiles, limit: options.reviewLimit, by: Self.largeSort)
                    }
                    if metadata.allocatedBytes > 0, metadata.modifiedAt <= cutoff {
                        Self.retain(item, in: &staleFiles, limit: options.reviewLimit, by: Self.staleSort)
                    }
                case .other:
                    continue
                }
            }
            if directoryRead.wasTruncated {
                issues.insert(.entryLimitReached)
                break scanLoop
            }
            if let terminationIssue = directoryRead.terminationIssue {
                issues.insert(terminationIssue)
                break scanLoop
            }
        }

        guard Self.matchesConfirmedRoot(root) else {
            return emptyReport(root: root, now: now, issue: .rootIdentityChanged)
        }
        return CloudLocalInventoryReport(
            root: root,
            generatedAt: now,
            scannedEntryCount: scannedEntries,
            directoryCount: directoryCount,
            fileCount: fileCount,
            skippedSymbolicLinkCount: skippedSymlinks,
            unreadableEntryCount: unreadableEntries,
            zeroAllocatedBlockFileCount: zeroAllocatedBlocks,
            sharedFileIdentityCount: sharedFileIdentities,
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            largeFiles: largeFiles,
            staleFiles: staleFiles,
            issues: issues.sorted { $0.rawValue < $1.rawValue },
            nonClaims: Self.nonClaims
        )
    }

    private func emptyReport(
        root: CloudConfirmedStorageRoot,
        now: Date,
        issue: CloudLocalInventoryIssue
    ) -> CloudLocalInventoryReport {
        CloudLocalInventoryReport(
            root: root,
            generatedAt: now,
            scannedEntryCount: 0,
            directoryCount: 0,
            fileCount: 0,
            skippedSymbolicLinkCount: 0,
            unreadableEntryCount: 0,
            zeroAllocatedBlockFileCount: 0,
            sharedFileIdentityCount: 0,
            logicalBytes: 0,
            allocatedBytes: 0,
            largeFiles: [],
            staleFiles: [],
            issues: [issue],
            nonClaims: Self.nonClaims
        )
    }

    private static func retain(
        _ item: CloudLocalFileReview,
        in items: inout [CloudLocalFileReview],
        limit: Int,
        by areInIncreasingOrder: (CloudLocalFileReview, CloudLocalFileReview) -> Bool
    ) {
        items.append(item)
        items.sort(by: areInIncreasingOrder)
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    private static func largeSort(_ lhs: CloudLocalFileReview, _ rhs: CloudLocalFileReview) -> Bool {
        if lhs.allocatedBytes != rhs.allocatedBytes { return lhs.allocatedBytes > rhs.allocatedBytes }
        if lhs.logicalBytes != rhs.logicalBytes { return lhs.logicalBytes > rhs.logicalBytes }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }

    private static func staleSort(_ lhs: CloudLocalFileReview, _ rhs: CloudLocalFileReview) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
        return largeSort(lhs, rhs)
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(max(0, rhs))
        return result.overflow ? Int64.max : result.partialValue
    }

    private static func matchesConfirmedRoot(_ root: CloudConfirmedStorageRoot) -> Bool {
        guard let metadata = CloudLocalMetadata.read(root.candidate.url) else { return false }
        return metadata.kind == .directory && metadata.identity == root.candidate.identity
    }
}

private enum CloudLocalFileKind {
    case directory
    case regularFile
    case symbolicLink
    case other
}

private struct CloudLocalMetadata {
    let kind: CloudLocalFileKind
    let identity: CloudRootIdentity
    let logicalBytes: Int64
    let allocatedBytes: Int64
    let modifiedAt: Date

    static func read(_ url: URL) -> CloudLocalMetadata? {
        #if canImport(Darwin)
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        let type = value.st_mode & S_IFMT
        let kind: CloudLocalFileKind
        switch type {
        case S_IFDIR: kind = .directory
        case S_IFREG: kind = .regularFile
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }
        let blocks = value.st_blocks > 0 ? Int64(value.st_blocks) : 0
        let allocation = blocks.multipliedReportingOverflow(by: 512)
        return CloudLocalMetadata(
            kind: kind,
            identity: CloudRootIdentity(deviceID: UInt64(value.st_dev), inode: UInt64(value.st_ino)),
            logicalBytes: max(0, Int64(value.st_size)),
            allocatedBytes: allocation.overflow ? Int64.max : allocation.partialValue,
            modifiedAt: Date(
                timeIntervalSince1970: TimeInterval(value.st_mtimespec.tv_sec)
                    + TimeInterval(value.st_mtimespec.tv_nsec) / 1_000_000_000
            )
        )
        #else
        return nil
        #endif
    }
}

private struct CloudLocalDirectoryRead {
    let names: [String]
    let invalidNameCount: Int
    let wasTruncated: Bool
    let terminationIssue: CloudLocalInventoryIssue?
}

private enum CloudLocalDirectoryReader {
    static func read(
        _ url: URL,
        limit: Int,
        deadlineNanos: UInt64
    ) throws -> CloudLocalDirectoryRead {
        #if canImport(Darwin)
        guard limit > 0 else {
            return CloudLocalDirectoryRead(
                names: [],
                invalidNameCount: 0,
                wasTruncated: true,
                terminationIssue: nil
            )
        }
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw currentPOSIXError() }
        guard let stream = fdopendir(descriptor) else {
            let error = currentPOSIXError()
            close(descriptor)
            throw error
        }
        defer { closedir(stream) }

        var names: [String] = []
        names.reserveCapacity(min(limit, 1_024))
        var invalidNameCount = 0
        var wasTruncated = false
        var consumedEntryCount = 0
        var terminationIssue: CloudLocalInventoryIssue?
        while let entry = readdir(stream) {
            if Task.isCancelled {
                terminationIssue = .cancelled
                break
            }
            if DispatchTime.now().uptimeNanoseconds >= deadlineNanos {
                terminationIssue = .timeLimitReached
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer -> String? in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)
                ) { String(validatingCString: $0) }
            }
            if name == "." || name == ".." { continue }
            if consumedEntryCount == limit {
                wasTruncated = true
                break
            }
            consumedEntryCount += 1
            guard let name else {
                invalidNameCount += 1
                continue
            }
            names.append(name)
        }
        names.sort()
        return CloudLocalDirectoryRead(
            names: names,
            invalidNameCount: invalidNameCount,
            wasTruncated: wasTruncated,
            terminationIssue: terminationIssue
        )
        #else
        throw POSIXError(.ENOTSUP)
        #endif
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
