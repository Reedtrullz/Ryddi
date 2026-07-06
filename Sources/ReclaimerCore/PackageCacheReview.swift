import Foundation

public enum PackageCacheManager: String, Codable, CaseIterable, Hashable, Sendable {
    case homebrew
    case npm
    case pnpm
    case yarn
    case pip
    case cargo
    case go
    case gradle
    case maven
    case cocoaPods
    case swiftPM
    case playwright
    case other

    public var label: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .npm: return "npm"
        case .pnpm: return "pnpm"
        case .yarn: return "Yarn"
        case .pip: return "pip"
        case .cargo: return "Cargo"
        case .go: return "Go"
        case .gradle: return "Gradle"
        case .maven: return "Maven"
        case .cocoaPods: return "CocoaPods"
        case .swiftPM: return "SwiftPM"
        case .playwright: return "Playwright"
        case .other: return "Other"
        }
    }

    public var nativeCleanupHint: String {
        switch self {
        case .homebrew: return "Prefer `brew cleanup --dry-run` before `brew cleanup`."
        case .npm: return "Prefer `npm cache verify`; use `npm cache clean --force` only deliberately."
        case .pnpm: return "Prefer `pnpm store status` and `pnpm store prune`."
        case .yarn: return "Prefer `yarn cache clean` or project-specific Yarn guidance."
        case .pip: return "Prefer `pip cache info` and `pip cache purge`."
        case .cargo: return "Prefer Cargo-owned cache cleanup tools and avoid deleting credentials/config."
        case .go: return "Prefer `go clean -modcache` only after confirming module cache can be rebuilt."
        case .gradle: return "Prefer Gradle cleanup guidance and avoid deleting active daemon/config state."
        case .maven: return "Prefer Maven-owned local repository cleanup; expect dependencies to redownload."
        case .cocoaPods: return "Prefer `pod cache list` and `pod cache clean`."
        case .swiftPM: return "Prefer SwiftPM/Xcode-derived cleanup paths over raw package-state deletion."
        case .playwright: return "Prefer Playwright install/cache commands and confirm browsers can be redownloaded."
        case .other: return "Use the owning tool's cleanup command where available."
        }
    }
}

public enum PackageCacheKind: String, Codable, CaseIterable, Hashable, Sendable {
    case downloadCache
    case packageStore
    case buildCache
    case metadataCache
    case binaryCache
    case otherCache

    public var label: String {
        switch self {
        case .downloadCache: return "Download cache"
        case .packageStore: return "Package store"
        case .buildCache: return "Build cache"
        case .metadataCache: return "Metadata cache"
        case .binaryCache: return "Binary cache"
        case .otherCache: return "Other cache"
        }
    }
}

public struct PackageCacheItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String
    public let manager: PackageCacheManager
    public let kind: PackageCacheKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let modificationDate: Date?
    public let signals: [String]
    public let recommendation: String
    public let guidance: [String]

    public init(
        id: String = UUID().uuidString,
        path: String,
        displayName: String,
        manager: PackageCacheManager,
        kind: PackageCacheKind,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        modificationDate: Date? = nil,
        signals: [String],
        recommendation: String,
        guidance: [String]
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.manager = manager
        self.kind = kind
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.modificationDate = modificationDate
        self.signals = signals
        self.recommendation = recommendation
        self.guidance = guidance
    }
}

public struct PackageCacheRootSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let manager: PackageCacheManager
    public let rootPath: String
    public let permissionState: PermissionState
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let nativeCleanupHint: String
    public let note: String

    public init(
        id: String = UUID().uuidString,
        manager: PackageCacheManager,
        rootPath: String,
        permissionState: PermissionState,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        nativeCleanupHint: String,
        note: String
    ) {
        self.id = id
        self.manager = manager
        self.rootPath = rootPath
        self.permissionState = permissionState
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.nativeCleanupHint = nativeCleanupHint
        self.note = note
    }
}

public struct PackageCacheProtectedConfigRoot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let manager: PackageCacheManager
    public let path: String
    public let permissionState: PermissionState
    public let note: String

    public init(
        id: String = UUID().uuidString,
        manager: PackageCacheManager,
        path: String,
        permissionState: PermissionState,
        note: String
    ) {
        self.id = id
        self.manager = manager
        self.path = path
        self.permissionState = permissionState
        self.note = note
    }
}

public struct PackageCacheSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let itemCount: Int
    public let allocatedSize: Int64

    public init(name: String, itemCount: Int, allocatedSize: Int64) {
        self.name = name
        self.itemCount = itemCount
        self.allocatedSize = allocatedSize
    }
}

public struct PackageCacheReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let itemCount: Int
    public let displayedItemCount: Int
    public let candidateBytes: Int64
    public let rootSummaries: [PackageCacheRootSummary]
    public let managerSummaries: [PackageCacheSummary]
    public let kindSummaries: [PackageCacheSummary]
    public let largestItems: [PackageCacheItem]
    public let protectedConfigRoots: [PackageCacheProtectedConfigRoot]
    public let guidance: [String]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        itemCount: Int,
        displayedItemCount: Int,
        candidateBytes: Int64,
        rootSummaries: [PackageCacheRootSummary],
        managerSummaries: [PackageCacheSummary],
        kindSummaries: [PackageCacheSummary],
        largestItems: [PackageCacheItem],
        protectedConfigRoots: [PackageCacheProtectedConfigRoot],
        guidance: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.itemCount = itemCount
        self.displayedItemCount = displayedItemCount
        self.candidateBytes = candidateBytes
        self.rootSummaries = rootSummaries
        self.managerSummaries = managerSummaries
        self.kindSummaries = kindSummaries
        self.largestItems = largestItems
        self.protectedConfigRoots = protectedConfigRoots
        self.guidance = guidance
        self.nonClaims = nonClaims
    }
}

public struct PackageCacheReviewOptions: Hashable, Sendable {
    public let roots: [URL]
    public let protectedConfigRoots: [URL]
    public let limit: Int
    public let measurementDepth: Int
    public let includeMissingRoots: Bool

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil,
        protectedConfigRoots: [URL]? = nil,
        limit: Int = 50,
        measurementDepth: Int = 7,
        includeMissingRoots: Bool = true
    ) {
        let standardizedHome = home.standardizedFileURL
        self.roots = (roots ?? Self.defaultCacheRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.protectedConfigRoots = (protectedConfigRoots ?? Self.defaultProtectedConfigRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.limit = max(1, min(limit, 500))
        self.measurementDepth = max(0, min(measurementDepth, 16))
        self.includeMissingRoots = includeMissingRoots
    }

    public static func defaultCacheRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Caches/Homebrew"),
            home.appendingPathComponent(".npm/_cacache"),
            home.appendingPathComponent("Library/pnpm/store"),
            home.appendingPathComponent(".pnpm-store"),
            home.appendingPathComponent("Library/Caches/Yarn"),
            home.appendingPathComponent(".yarn/cache"),
            home.appendingPathComponent("Library/Caches/pip"),
            home.appendingPathComponent(".cache/pip"),
            home.appendingPathComponent(".cargo/registry"),
            home.appendingPathComponent(".cargo/git"),
            home.appendingPathComponent("go/pkg/mod/cache"),
            home.appendingPathComponent(".gradle/caches"),
            home.appendingPathComponent(".m2/repository"),
            home.appendingPathComponent("Library/Caches/CocoaPods"),
            home.appendingPathComponent(".cocoapods/repos"),
            home.appendingPathComponent("Library/Caches/org.swift.swiftpm"),
            home.appendingPathComponent(".swiftpm/cache"),
            home.appendingPathComponent("Library/Caches/ms-playwright")
        ]
    }

    public static func defaultProtectedConfigRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent(".npmrc"),
            home.appendingPathComponent(".pnpmrc"),
            home.appendingPathComponent(".yarnrc"),
            home.appendingPathComponent(".yarnrc.yml"),
            home.appendingPathComponent(".pypirc"),
            home.appendingPathComponent(".config/pip"),
            home.appendingPathComponent(".cargo/config"),
            home.appendingPathComponent(".cargo/config.toml"),
            home.appendingPathComponent(".cargo/credentials"),
            home.appendingPathComponent(".cargo/credentials.toml"),
            home.appendingPathComponent(".gradle/gradle.properties"),
            home.appendingPathComponent(".m2/settings.xml"),
            home.appendingPathComponent(".cocoapods"),
            home.appendingPathComponent(".swiftpm/configuration")
        ]
    }
}

public final class PackageCacheReviewScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func review(
        options: PackageCacheReviewOptions = PackageCacheReviewOptions(),
        createdAt: Date = Date()
    ) -> PackageCacheReviewReport {
        var summaries: [PackageCacheRootSummary] = []
        var items: [PackageCacheItem] = []

        for root in options.roots {
            let result = inspect(root: root, measurementDepth: options.measurementDepth)
            if result.summary.permissionState != .missing || options.includeMissingRoots {
                summaries.append(result.summary)
            }
            items.append(contentsOf: result.items)
        }

        let sortedItems = items.sorted { lhs, rhs in
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.path < rhs.path
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        let logical = sortedItems.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = sortedItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let measuredCount = sortedItems.reduce(0) { $0 + max(1, $1.itemCount) }
        let protectedRoots = options.protectedConfigRoots.map { protectedConfigRoot(for: $0) }

        return PackageCacheReviewReport(
            createdAt: createdAt,
            totalLogicalSize: logical,
            totalAllocatedSize: allocated,
            itemCount: measuredCount,
            displayedItemCount: min(sortedItems.count, options.limit),
            candidateBytes: allocated,
            rootSummaries: summaries,
            managerSummaries: Self.managerSummaries(for: sortedItems),
            kindSummaries: Self.kindSummaries(for: sortedItems),
            largestItems: Array(sortedItems.prefix(options.limit)),
            protectedConfigRoots: protectedRoots,
            guidance: Self.guidance,
            nonClaims: Self.nonClaims
        )
    }

    private func inspect(root: URL, measurementDepth: Int) -> (summary: PackageCacheRootSummary, items: [PackageCacheItem]) {
        let root = root.standardizedFileURL
        let manager = Self.manager(for: root)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return (
                PackageCacheRootSummary(
                    manager: manager,
                    rootPath: root.path,
                    permissionState: .missing,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: manager.nativeCleanupHint,
                    note: "Package cache root does not exist at \(root.path)."
                ),
                []
            )
        }
        guard isDirectory.boolValue else {
            return (
                PackageCacheRootSummary(
                    manager: manager,
                    rootPath: root.path,
                    permissionState: .unknown,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: manager.nativeCleanupHint,
                    note: "Configured package cache root is not a directory: \(root.path)."
                ),
                []
            )
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            return (
                PackageCacheRootSummary(
                    manager: manager,
                    rootPath: root.path,
                    permissionState: .denied,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: manager.nativeCleanupHint,
                    note: "Package cache root is not readable with current permissions: \(root.path)."
                ),
                []
            )
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: packageCacheResourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return (
                PackageCacheRootSummary(
                    manager: manager,
                    rootPath: root.path,
                    permissionState: .denied,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    nativeCleanupHint: manager.nativeCleanupHint,
                    note: "Could not list package cache root at \(root.path)."
                ),
                []
            )
        }

        let rootItems = children.map { item(for: $0, manager: manager, measurementDepth: measurementDepth) }
        let logical = rootItems.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = rootItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let count = rootItems.reduce(0) { $0 + max(1, $1.itemCount) }
        return (
            PackageCacheRootSummary(
                manager: manager,
                rootPath: root.path,
                permissionState: .readable,
                logicalSize: logical,
                allocatedSize: allocated,
                itemCount: count,
                nativeCleanupHint: manager.nativeCleanupHint,
                note: "Measured immediate package-cache entries under \(root.path)."
            ),
            rootItems
        )
    }

    private func item(for url: URL, manager: PackageCacheManager, measurementDepth: Int) -> PackageCacheItem {
        let values = try? url.resourceValues(forKeys: Set(packageCacheResourceKeys))
        let measurement = measure(url: url, maxDepth: measurementDepth)
        let kind = Self.kind(for: url, manager: manager)
        let isSymbolicLink = values?.isSymbolicLink ?? false
        var signals = ["package-cache", manager.rawValue, kind.rawValue]
        if isSymbolicLink {
            signals.append("symlink-not-followed")
        }
        return PackageCacheItem(
            path: url.path,
            displayName: url.lastPathComponent,
            manager: manager,
            kind: kind,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            itemCount: measurement.itemCount,
            isDirectory: values?.isDirectory ?? false,
            isSymbolicLink: isSymbolicLink,
            modificationDate: values?.contentModificationDate,
            signals: signals,
            recommendation: "\(manager.nativeCleanupHint) Use a dry-run cleanup plan before removal.",
            guidance: [
                "Package cache data is often rebuildable, but nearby config/auth files and project lockfiles are not part of this cache review.",
                "Prefer the owning package manager's cleanup command over raw deletion."
            ] + (isSymbolicLink ? ["Symbolic link was not followed while measuring."] : [])
        )
    }

    private func protectedConfigRoot(for url: URL) -> PackageCacheProtectedConfigRoot {
        let url = url.standardizedFileURL
        let manager = Self.manager(for: url)
        var isDirectory: ObjCBool = false
        let state: PermissionState
        let note: String
        if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            state = .missing
            note = "Protected package-manager config/auth path is not present."
        } else if !fileManager.isReadableFile(atPath: url.path) {
            state = .denied
            note = "Protected package-manager config/auth path exists but is not readable; it remains outside cache review."
        } else {
            state = .readable
            note = "Protected package-manager config/auth path may contain tokens, credentials, registries, settings, or project behavior; it is intentionally not measured as cache."
        }
        return PackageCacheProtectedConfigRoot(manager: manager, path: url.path, permissionState: state, note: note)
    }

    private func measure(url: URL, maxDepth: Int) -> PackageCacheMeasurement {
        guard let values = try? url.resourceValues(forKeys: Set(packageCacheResourceKeys)) else {
            return PackageCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        if values.isSymbolicLink == true {
            return PackageCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return PackageCacheMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }
        guard maxDepth > 0 else {
            return PackageCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: packageCacheResourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return PackageCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        for case let child as URL in enumerator {
            let depth = max(0, child.pathComponents.count - url.pathComponents.count)
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(packageCacheResourceKeys)) else { continue }
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
        return PackageCacheMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }

    private static func managerSummaries(for items: [PackageCacheItem]) -> [PackageCacheSummary] {
        PackageCacheManager.allCases.compactMap { manager in
            let matches = items.filter { $0.manager == manager }
            guard !matches.isEmpty else { return nil }
            return PackageCacheSummary(
                name: manager.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func kindSummaries(for items: [PackageCacheItem]) -> [PackageCacheSummary] {
        PackageCacheKind.allCases.compactMap { kind in
            let matches = items.filter { $0.kind == kind }
            guard !matches.isEmpty else { return nil }
            return PackageCacheSummary(
                name: kind.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func manager(for url: URL) -> PackageCacheManager {
        let lower = url.path.lowercased()
        if lower.contains("homebrew") { return .homebrew }
        if lower.contains("/.npm") || lower.contains("/npm/") || lower.hasSuffix("/npm") { return .npm }
        if lower.contains("pnpm") { return .pnpm }
        if lower.contains("yarn") { return .yarn }
        if lower.contains("/pip") || lower.contains(".pypirc") { return .pip }
        if lower.contains("/.cargo") { return .cargo }
        if lower.contains("/go/pkg/mod") { return .go }
        if lower.contains("/.gradle") || lower.contains("/gradle/") { return .gradle }
        if lower.contains("/.m2") || lower.contains("/maven/") { return .maven }
        if lower.contains("cocoapods") { return .cocoaPods }
        if lower.contains("swiftpm") || lower.contains("org.swift.swiftpm") { return .swiftPM }
        if lower.contains("playwright") { return .playwright }
        return .other
    }

    private static func kind(for url: URL, manager: PackageCacheManager) -> PackageCacheKind {
        let lower = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        if lower.contains("/downloads") || name == "downloads" { return .downloadCache }
        if lower.contains("build-cache") || lower.contains("/build/") { return .buildCache }
        if lower.contains("/index") || lower.contains("/metadata") || lower.contains("/repos") || name.contains("index") { return .metadataCache }
        if manager == .playwright || lower.contains("ms-playwright") || lower.contains("/browsers") { return .binaryCache }
        if lower.contains("_cacache") || lower.contains("/store") || lower.contains("/registry") || lower.contains("/repository") || lower.contains("/pkg/mod") || lower.contains("/modules-") || lower.contains("/files-") {
            return .packageStore
        }
        return .otherCache
    }

    public static let guidance = [
        "Prefer package-manager cleanup commands over raw deletion.",
        "Review package-manager config/auth files separately; tokens, registries, credentials, mirrors, lockfiles, and project behavior are protected state.",
        "Expect caches to be redownloaded or rebuilt after cleanup, and verify network access before removing large package stores.",
        "Use Ryddi native-tool receipts for commands that support a safe preview or dry-run."
    ]

    public static let nonClaims = [
        "Package Cache Review is report-only; it does not delete, move, Trash, prune, purge, or modify package-manager files.",
        "Ryddi does not measure protected package-manager config/auth paths as cache because they can contain credentials, registry settings, mirrors, tokens, and project behavior.",
        "Package-cache classification is path-based and cannot prove the owning tool is idle or that all active handles are closed.",
        "Package cache size is not promised immediate free-space recovery because package managers, APFS snapshots, hard links, clones, and purgeable storage can affect accounting."
    ]
}

private struct PackageCacheMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private let packageCacheResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]
