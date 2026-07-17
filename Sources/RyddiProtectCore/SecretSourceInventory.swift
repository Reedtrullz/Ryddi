import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum SecretSourceKind: String, Codable, Hashable, Sendable {
    case dotenv
}

public enum SecretSourceInspectionEligibility: String, Codable, Hashable, Sendable {
    case eligible
}

/// Metadata emitted before any explicit content-inspection action.
public struct SecretSourceInventoryEntry: Hashable, Sendable {
    public let path: String
    public let fileIdentity: ProtectionFileIdentity
    public let fileSize: Int64
    public let posixMode: UInt32
    public let age: TimeInterval
    public let sourceKind: SecretSourceKind
    public let inspectionEligibility: SecretSourceInspectionEligibility

    init(
        path: String,
        fileIdentity: ProtectionFileIdentity,
        fileSize: Int64,
        posixMode: UInt32,
        age: TimeInterval,
        sourceKind: SecretSourceKind,
        inspectionEligibility: SecretSourceInspectionEligibility
    ) {
        self.path = path
        self.fileIdentity = fileIdentity
        self.fileSize = fileSize
        self.posixMode = posixMode
        self.age = age
        self.sourceKind = sourceKind
        self.inspectionEligibility = inspectionEligibility
    }
}

public struct SecretSourceInventoryBudget: Hashable, Sendable {
    public static let hardMaximumDepth = 64
    public static let hardMaximumVisitedEntryCount = 100_000
    public static let hardMaximumElapsedTime: TimeInterval = 30

    public let maximumDepth: Int
    /// Counts every visited filesystem entry, including directories and rejected special files.
    public let maximumVisitedEntryCount: Int
    public let maximumElapsedTime: TimeInterval

    public init(
        maximumDepth: Int = 8,
        maximumVisitedEntryCount: Int = 10_000,
        maximumElapsedTime: TimeInterval = 2
    ) {
        self.maximumDepth = Swift.min(
            Swift.max(0, maximumDepth),
            Self.hardMaximumDepth
        )
        self.maximumVisitedEntryCount = Swift.min(
            Swift.max(0, maximumVisitedEntryCount),
            Self.hardMaximumVisitedEntryCount
        )
        if maximumElapsedTime.isNaN {
            self.maximumElapsedTime = 0
        } else {
            self.maximumElapsedTime = Swift.min(
                Swift.max(0, maximumElapsedTime),
                Self.hardMaximumElapsedTime
            )
        }
    }
}

public enum SecretSourceInventoryTruncationReason: String, CaseIterable, Hashable, Sendable {
    case maximumDepth
    case maximumVisitedEntryCount
    case maximumElapsedTime
}

public struct SecretSourceInventoryCoverage: Hashable, Sendable {
    public let selectedRootCount: Int
    public let visitedEntryCount: Int
    public let skippedEntryCount: Int
    public let unreadableEntryCount: Int
    public let metadataFailureCount: Int
    public let truncationReasons: [SecretSourceInventoryTruncationReason]

    init(
        selectedRootCount: Int,
        visitedEntryCount: Int,
        skippedEntryCount: Int,
        unreadableEntryCount: Int,
        metadataFailureCount: Int,
        truncationReasons: [SecretSourceInventoryTruncationReason]
    ) {
        self.selectedRootCount = selectedRootCount
        self.visitedEntryCount = visitedEntryCount
        self.skippedEntryCount = skippedEntryCount
        self.unreadableEntryCount = unreadableEntryCount
        self.metadataFailureCount = metadataFailureCount
        self.truncationReasons = truncationReasons
    }

    public var isTruncated: Bool {
        !truncationReasons.isEmpty
    }

    public var isComplete: Bool {
        !isTruncated && unreadableEntryCount == 0 && metadataFailureCount == 0
    }
}

public struct SecretSourceInventoryResult: Sendable {
    public let entries: [SecretSourceInventoryEntry]
    public let coverage: SecretSourceInventoryCoverage

    init(entries: [SecretSourceInventoryEntry], coverage: SecretSourceInventoryCoverage) {
        self.entries = entries
        self.coverage = coverage
    }
}

public struct SecretSourceInventory: Sendable {
    public static let maximumEligibleFileSize: Int64 = 1_048_576

    private let monotonicTime: @Sendable () -> TimeInterval

    public init() {
        self.monotonicTime = { ProcessInfo.processInfo.systemUptime }
    }

    init(monotonicTime: @escaping @Sendable () -> TimeInterval) {
        self.monotonicTime = monotonicTime
    }

    public func scan(
        roots: [URL],
        budget: SecretSourceInventoryBudget = SecretSourceInventoryBudget(),
        referenceDate: Date = Date()
    ) -> SecretSourceInventoryResult {
        scan(selectedRoots: roots, budget: budget, referenceDate: referenceDate)
    }

    public func scan(
        selectedRoots: [URL],
        budget: SecretSourceInventoryBudget = SecretSourceInventoryBudget(),
        referenceDate: Date = Date()
    ) -> SecretSourceInventoryResult {
        #if canImport(Darwin)
        scanDarwin(selectedRoots: selectedRoots, budget: budget, referenceDate: referenceDate)
        #else
        let failureCount = selectedRoots.count
        return SecretSourceInventoryResult(
            entries: [],
            coverage: SecretSourceInventoryCoverage(
                selectedRootCount: selectedRoots.count,
                visitedEntryCount: 0,
                skippedEntryCount: failureCount,
                unreadableEntryCount: 0,
                metadataFailureCount: failureCount,
                truncationReasons: []
            )
        )
        #endif
    }
}

#if canImport(Darwin)
private extension SecretSourceInventory {
    struct PendingEntry {
        let path: String
        let name: String
        let depth: Int
    }

    struct DirectoryReadResult {
        let names: [String]
        let hasMoreEntries: Bool
        let elapsedTimeExceeded: Bool
        let metadataFailureCount: Int
    }

    static let excludedDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".gradle",
        ".hg",
        ".next",
        ".svn",
        ".venv",
        "build",
        "carthage",
        "deriveddata",
        "dist",
        "node_modules",
        "pods",
        "target",
        "vendor",
        "venv"
    ]

    func scanDarwin(
        selectedRoots: [URL],
        budget: SecretSourceInventoryBudget,
        referenceDate: Date
    ) -> SecretSourceInventoryResult {
        let startedAt = monotonicTime()
        let referenceTimestamp = referenceDate.timeIntervalSince1970
        var entries = [SecretSourceInventoryEntry]()
        var pending = [PendingEntry]()
        var queuedPaths = Set<String>()
        var visitedEntryCount = 0
        var skippedEntryCount = 0
        var unreadableEntryCount = 0
        var metadataFailureCount = 0
        var truncationReasons = Set<SecretSourceInventoryTruncationReason>()

        guard referenceTimestamp.isFinite else {
            return makeResult(
                entries: [],
                selectedRootCount: selectedRoots.count,
                visitedEntryCount: 0,
                skippedEntryCount: selectedRoots.count,
                unreadableEntryCount: 0,
                metadataFailureCount: selectedRoots.count,
                truncationReasons: []
            )
        }

        if !selectedRoots.isEmpty, budget.maximumVisitedEntryCount == 0 {
            truncationReasons.insert(.maximumVisitedEntryCount)
        } else {
            for root in selectedRoots {
                if timeExceeded(startedAt: startedAt, budget: budget) {
                    truncationReasons.insert(.maximumElapsedTime)
                    break
                }
                guard pending.count < budget.maximumVisitedEntryCount else {
                    truncationReasons.insert(.maximumVisitedEntryCount)
                    break
                }
                guard root.isFileURL else {
                    skippedEntryCount += 1
                    metadataFailureCount += 1
                    continue
                }
                let path = root.path
                guard !path.isEmpty, queuedPaths.insert(path).inserted else {
                    continue
                }
                pending.append(PendingEntry(
                    path: path,
                    name: root.lastPathComponent,
                    depth: 0
                ))
            }
        }

        var cursor = 0
        traversal: while cursor < pending.count {
            if timeExceeded(startedAt: startedAt, budget: budget) {
                truncationReasons.insert(.maximumElapsedTime)
                break
            }

            let current = pending[cursor]
            cursor += 1
            visitedEntryCount += 1

            guard let metadata = lstatMetadata(at: current.path) else {
                skippedEntryCount += 1
                metadataFailureCount += 1
                continue
            }

            switch metadata.st_mode & S_IFMT {
            case S_IFLNK:
                skippedEntryCount += 1

            case S_IFDIR:
                if Self.excludedDirectoryNames.contains(current.name.lowercased()) {
                    skippedEntryCount += 1
                    continue
                }

                if current.depth >= budget.maximumDepth {
                    let depthProbe = readDirectory(
                        at: current.path,
                        expectedMetadata: metadata,
                        maximumNames: 0,
                        startedAt: startedAt,
                        budget: budget
                    )
                    metadataFailureCount += depthProbe.metadataFailureCount
                    skippedEntryCount += depthProbe.metadataFailureCount
                    if depthProbe.elapsedTimeExceeded {
                        truncationReasons.insert(.maximumElapsedTime)
                        break traversal
                    }
                    if depthProbe.hasMoreEntries {
                        truncationReasons.insert(.maximumDepth)
                    }
                    continue
                }

                let remainingCapacity = budget.maximumVisitedEntryCount - pending.count
                guard remainingCapacity > 0 else {
                    truncationReasons.insert(.maximumVisitedEntryCount)
                    continue
                }
                let directoryResult = readDirectory(
                    at: current.path,
                    expectedMetadata: metadata,
                    maximumNames: remainingCapacity,
                    startedAt: startedAt,
                    budget: budget
                )
                metadataFailureCount += directoryResult.metadataFailureCount
                skippedEntryCount += directoryResult.metadataFailureCount
                if directoryResult.hasMoreEntries {
                    truncationReasons.insert(.maximumVisitedEntryCount)
                }
                if directoryResult.elapsedTimeExceeded {
                    truncationReasons.insert(.maximumElapsedTime)
                    break traversal
                }

                for name in directoryResult.names.sorted() {
                    let childPath = URL(fileURLWithPath: current.path, isDirectory: true)
                        .appendingPathComponent(name, isDirectory: false)
                        .path
                    guard childPath != current.path, queuedPaths.insert(childPath).inserted else {
                        continue
                    }
                    pending.append(PendingEntry(
                        path: childPath,
                        name: name,
                        depth: current.depth + 1
                    ))
                }

            case S_IFREG:
                guard Self.isDotenvName(current.name) else {
                    continue
                }
                guard metadata.st_size >= 0,
                      Int64(metadata.st_size) <= Self.maximumEligibleFileSize else {
                    skippedEntryCount += 1
                    continue
                }
                guard isReadable(at: current.path, metadata: metadata) else {
                    skippedEntryCount += 1
                    unreadableEntryCount += 1
                    continue
                }
                guard let verifiedMetadata = lstatMetadata(at: current.path),
                      sameFileMetadata(metadata, verifiedMetadata) else {
                    skippedEntryCount += 1
                    metadataFailureCount += 1
                    continue
                }
                guard !timeExceeded(startedAt: startedAt, budget: budget) else {
                    truncationReasons.insert(.maximumElapsedTime)
                    break traversal
                }
                guard let age = age(
                    for: verifiedMetadata,
                    referenceTimestamp: referenceTimestamp
                ) else {
                    skippedEntryCount += 1
                    metadataFailureCount += 1
                    continue
                }

                entries.append(SecretSourceInventoryEntry(
                    path: current.path,
                    fileIdentity: ProtectionFileIdentity(
                        deviceID: UInt64(verifiedMetadata.st_dev),
                        fileID: UInt64(verifiedMetadata.st_ino),
                        kind: .regularFile,
                        standardizedPath: current.path
                    ),
                    fileSize: Int64(verifiedMetadata.st_size),
                    posixMode: UInt32(verifiedMetadata.st_mode & mode_t(0o7777)),
                    age: age,
                    sourceKind: .dotenv,
                    inspectionEligibility: .eligible
                ))

            default:
                skippedEntryCount += 1
            }
        }

        return makeResult(
            entries: entries.sorted { $0.path < $1.path },
            selectedRootCount: selectedRoots.count,
            visitedEntryCount: visitedEntryCount,
            skippedEntryCount: skippedEntryCount,
            unreadableEntryCount: unreadableEntryCount,
            metadataFailureCount: metadataFailureCount,
            truncationReasons: truncationReasons
        )
    }

    func readDirectory(
        at path: String,
        expectedMetadata: Darwin.stat,
        maximumNames: Int,
        startedAt: TimeInterval,
        budget: SecretSourceInventoryBudget
    ) -> DirectoryReadResult {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        let descriptor = path.withCString { Darwin.open($0, flags) }
        guard descriptor >= 0 else {
            return DirectoryReadResult(
                names: [],
                hasMoreEntries: false,
                elapsedTimeExceeded: false,
                metadataFailureCount: 1
            )
        }

        var openedMetadata = Darwin.stat()
        guard Darwin.fstat(descriptor, &openedMetadata) == 0,
              openedMetadata.st_mode & S_IFMT == S_IFDIR,
              openedMetadata.st_dev == expectedMetadata.st_dev,
              openedMetadata.st_ino == expectedMetadata.st_ino else {
            Darwin.close(descriptor)
            return DirectoryReadResult(
                names: [],
                hasMoreEntries: false,
                elapsedTimeExceeded: false,
                metadataFailureCount: 1
            )
        }

        guard let directory = Darwin.fdopendir(descriptor) else {
            Darwin.close(descriptor)
            return DirectoryReadResult(
                names: [],
                hasMoreEntries: false,
                elapsedTimeExceeded: false,
                metadataFailureCount: 1
            )
        }

        var names = [String]()
        var hasMoreEntries = false
        var elapsedTimeExceeded = false
        var metadataFailureCount = 0

        while true {
            if timeExceeded(startedAt: startedAt, budget: budget) {
                elapsedTimeExceeded = true
                break
            }
            errno = 0
            guard let rawEntry = Darwin.readdir(directory) else {
                if errno != 0 {
                    metadataFailureCount += 1
                }
                break
            }
            guard let name = directoryEntryName(rawEntry) else {
                metadataFailureCount += 1
                continue
            }
            guard name != ".", name != ".." else {
                continue
            }
            guard names.count < maximumNames else {
                hasMoreEntries = true
                break
            }
            names.append(name)
        }

        if Darwin.closedir(directory) != 0 {
            metadataFailureCount += 1
        }
        return DirectoryReadResult(
            names: names,
            hasMoreEntries: hasMoreEntries,
            elapsedTimeExceeded: elapsedTimeExceeded,
            metadataFailureCount: metadataFailureCount
        )
    }

    func lstatMetadata(at path: String) -> Darwin.stat? {
        var metadata = Darwin.stat()
        let result = path.withCString { Darwin.lstat($0, &metadata) }
        return result == 0 ? metadata : nil
    }

    func isReadable(at path: String, metadata: Darwin.stat) -> Bool {
        let readBits = S_IRUSR | S_IRGRP | S_IROTH
        guard metadata.st_mode & readBits != 0 else {
            return false
        }
        return path.withCString { Darwin.access($0, R_OK) } == 0
    }

    func sameFileMetadata(_ first: Darwin.stat, _ second: Darwin.stat) -> Bool {
        first.st_dev == second.st_dev
            && first.st_ino == second.st_ino
            && first.st_mode == second.st_mode
            && first.st_size == second.st_size
            && first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec
            && first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
    }

    func age(for metadata: Darwin.stat, referenceTimestamp: TimeInterval) -> TimeInterval? {
        guard metadata.st_mtimespec.tv_nsec >= 0,
              metadata.st_mtimespec.tv_nsec < 1_000_000_000 else {
            return nil
        }
        let modificationTimestamp = TimeInterval(metadata.st_mtimespec.tv_sec)
            + (TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000)
        guard modificationTimestamp.isFinite else {
            return nil
        }
        return Swift.max(0, referenceTimestamp - modificationTimestamp)
    }

    func timeExceeded(
        startedAt: TimeInterval,
        budget: SecretSourceInventoryBudget
    ) -> Bool {
        let currentTime = monotonicTime()
        guard startedAt.isFinite,
              currentTime.isFinite,
              currentTime >= startedAt else {
            return true
        }
        return currentTime - startedAt >= budget.maximumElapsedTime
    }

    func makeResult(
        entries: [SecretSourceInventoryEntry],
        selectedRootCount: Int,
        visitedEntryCount: Int,
        skippedEntryCount: Int,
        unreadableEntryCount: Int,
        metadataFailureCount: Int,
        truncationReasons: Set<SecretSourceInventoryTruncationReason>
    ) -> SecretSourceInventoryResult {
        let orderedReasons = SecretSourceInventoryTruncationReason.allCases.filter {
            truncationReasons.contains($0)
        }
        return SecretSourceInventoryResult(
            entries: entries,
            coverage: SecretSourceInventoryCoverage(
                selectedRootCount: selectedRootCount,
                visitedEntryCount: visitedEntryCount,
                skippedEntryCount: skippedEntryCount,
                unreadableEntryCount: unreadableEntryCount,
                metadataFailureCount: metadataFailureCount,
                truncationReasons: orderedReasons
            )
        )
    }

    static func isDotenvName(_ name: String) -> Bool {
        guard name == ".env" || name.hasPrefix(".env.") else {
            return false
        }
        return name != ".env.example"
            && name != ".env.sample"
            && !name.hasPrefix(".env.example.")
            && !name.hasPrefix(".env.sample.")
    }

    func directoryEntryName(_ entry: UnsafeMutablePointer<dirent>) -> String? {
        withUnsafePointer(to: entry.pointee.d_name) { namePointer in
            namePointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(entry.pointee.d_namlen) + 1
            ) { String(validatingCString: $0) }
        }
    }
}
#endif
