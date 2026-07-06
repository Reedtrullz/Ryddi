import Foundation

public enum BrowserCacheBrowser: String, Codable, CaseIterable, Hashable, Sendable {
    case chrome
    case firefox
    case safari
    case edge
    case brave
    case arc
    case webKit
    case other

    public var label: String {
        switch self {
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .safari: return "Safari"
        case .edge: return "Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        case .webKit: return "WebKit"
        case .other: return "Other"
        }
    }
}

public enum BrowserCacheKind: String, Codable, CaseIterable, Hashable, Sendable {
    case diskCache
    case codeCache
    case gpuCache
    case mediaCache
    case serviceWorkerCache
    case networkCache
    case otherCache

    public var label: String {
        switch self {
        case .diskCache: return "Disk cache"
        case .codeCache: return "Code cache"
        case .gpuCache: return "GPU cache"
        case .mediaCache: return "Media cache"
        case .serviceWorkerCache: return "Service worker cache"
        case .networkCache: return "Network cache"
        case .otherCache: return "Other cache"
        }
    }
}

public struct BrowserCacheItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let displayName: String
    public let browser: BrowserCacheBrowser
    public let kind: BrowserCacheKind
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
        browser: BrowserCacheBrowser,
        kind: BrowserCacheKind,
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
        self.browser = browser
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

public struct BrowserCacheRootSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let browser: BrowserCacheBrowser
    public let rootPath: String
    public let permissionState: PermissionState
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let itemCount: Int
    public let note: String

    public init(
        id: String = UUID().uuidString,
        browser: BrowserCacheBrowser,
        rootPath: String,
        permissionState: PermissionState,
        logicalSize: Int64,
        allocatedSize: Int64,
        itemCount: Int,
        note: String
    ) {
        self.id = id
        self.browser = browser
        self.rootPath = rootPath
        self.permissionState = permissionState
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.note = note
    }
}

public struct BrowserCacheProtectedProfileRoot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let browser: BrowserCacheBrowser
    public let path: String
    public let permissionState: PermissionState
    public let note: String

    public init(
        id: String = UUID().uuidString,
        browser: BrowserCacheBrowser,
        path: String,
        permissionState: PermissionState,
        note: String
    ) {
        self.id = id
        self.browser = browser
        self.path = path
        self.permissionState = permissionState
        self.note = note
    }
}

public struct BrowserCacheSummary: Codable, Hashable, Identifiable, Sendable {
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

public struct BrowserCacheReviewReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let itemCount: Int
    public let displayedItemCount: Int
    public let candidateBytes: Int64
    public let rootSummaries: [BrowserCacheRootSummary]
    public let browserSummaries: [BrowserCacheSummary]
    public let kindSummaries: [BrowserCacheSummary]
    public let largestItems: [BrowserCacheItem]
    public let protectedProfileRoots: [BrowserCacheProtectedProfileRoot]
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
        rootSummaries: [BrowserCacheRootSummary],
        browserSummaries: [BrowserCacheSummary],
        kindSummaries: [BrowserCacheSummary],
        largestItems: [BrowserCacheItem],
        protectedProfileRoots: [BrowserCacheProtectedProfileRoot],
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
        self.browserSummaries = browserSummaries
        self.kindSummaries = kindSummaries
        self.largestItems = largestItems
        self.protectedProfileRoots = protectedProfileRoots
        self.guidance = guidance
        self.nonClaims = nonClaims
    }
}

public struct BrowserCacheReviewOptions: Hashable, Sendable {
    public let roots: [URL]
    public let profileRoots: [URL]
    public let limit: Int
    public let measurementDepth: Int
    public let includeMissingRoots: Bool

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil,
        profileRoots: [URL]? = nil,
        limit: Int = 50,
        measurementDepth: Int = 7,
        includeMissingRoots: Bool = true
    ) {
        let standardizedHome = home.standardizedFileURL
        self.roots = (roots ?? Self.defaultCacheRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.profileRoots = (profileRoots ?? Self.defaultProfileRoots(home: standardizedHome)).map { $0.standardizedFileURL }
        self.limit = max(1, min(limit, 500))
        self.measurementDepth = max(0, min(measurementDepth, 16))
        self.includeMissingRoots = includeMissingRoots
    }

    public static func defaultCacheRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Caches/Google/Chrome"),
            home.appendingPathComponent("Library/Caches/com.google.Chrome"),
            home.appendingPathComponent("Library/Caches/Firefox"),
            home.appendingPathComponent("Library/Caches/com.apple.Safari"),
            home.appendingPathComponent("Library/Caches/com.apple.WebKit"),
            home.appendingPathComponent("Library/Caches/Microsoft Edge"),
            home.appendingPathComponent("Library/Caches/com.microsoft.edgemac"),
            home.appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser"),
            home.appendingPathComponent("Library/Caches/company.thebrowser.Browser")
        ]
    }

    public static func defaultProfileRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Application Support/Google/Chrome"),
            home.appendingPathComponent("Library/Application Support/Firefox"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Application Support/Microsoft Edge"),
            home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser"),
            home.appendingPathComponent("Library/Application Support/Arc")
        ]
    }
}

public final class BrowserCacheReviewScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func review(
        options: BrowserCacheReviewOptions = BrowserCacheReviewOptions(),
        createdAt: Date = Date()
    ) -> BrowserCacheReviewReport {
        var summaries: [BrowserCacheRootSummary] = []
        var items: [BrowserCacheItem] = []

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
        let protectedProfiles = options.profileRoots.map { protectedProfileRoot(for: $0) }

        return BrowserCacheReviewReport(
            createdAt: createdAt,
            totalLogicalSize: logical,
            totalAllocatedSize: allocated,
            itemCount: measuredCount,
            displayedItemCount: min(sortedItems.count, options.limit),
            candidateBytes: allocated,
            rootSummaries: summaries,
            browserSummaries: Self.browserSummaries(for: sortedItems),
            kindSummaries: Self.kindSummaries(for: sortedItems),
            largestItems: Array(sortedItems.prefix(options.limit)),
            protectedProfileRoots: protectedProfiles,
            guidance: Self.guidance,
            nonClaims: Self.nonClaims
        )
    }

    private func inspect(root: URL, measurementDepth: Int) -> (summary: BrowserCacheRootSummary, items: [BrowserCacheItem]) {
        let root = root.standardizedFileURL
        let browser = Self.browser(for: root)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return (
                BrowserCacheRootSummary(
                    browser: browser,
                    rootPath: root.path,
                    permissionState: .missing,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    note: "Cache root does not exist at \(root.path)."
                ),
                []
            )
        }
        guard isDirectory.boolValue else {
            return (
                BrowserCacheRootSummary(
                    browser: browser,
                    rootPath: root.path,
                    permissionState: .unknown,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    note: "Configured browser cache root is not a directory: \(root.path)."
                ),
                []
            )
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            return (
                BrowserCacheRootSummary(
                    browser: browser,
                    rootPath: root.path,
                    permissionState: .denied,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    note: "Browser cache root is not readable with current permissions: \(root.path)."
                ),
                []
            )
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: browserCacheResourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return (
                BrowserCacheRootSummary(
                    browser: browser,
                    rootPath: root.path,
                    permissionState: .denied,
                    logicalSize: 0,
                    allocatedSize: 0,
                    itemCount: 0,
                    note: "Could not list browser cache root at \(root.path)."
                ),
                []
            )
        }

        let rootItems = children.map { item(for: $0, browser: browser, measurementDepth: measurementDepth) }
        let logical = rootItems.reduce(Int64(0)) { $0 + $1.logicalSize }
        let allocated = rootItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let count = rootItems.reduce(0) { $0 + max(1, $1.itemCount) }
        return (
            BrowserCacheRootSummary(
                browser: browser,
                rootPath: root.path,
                permissionState: .readable,
                logicalSize: logical,
                allocatedSize: allocated,
                itemCount: count,
                note: "Measured immediate cache entries under \(root.path)."
            ),
            rootItems
        )
    }

    private func item(for url: URL, browser: BrowserCacheBrowser, measurementDepth: Int) -> BrowserCacheItem {
        let values = try? url.resourceValues(forKeys: Set(browserCacheResourceKeys))
        let measurement = measure(url: url, maxDepth: measurementDepth)
        let kind = Self.kind(for: url)
        let isSymbolicLink = values?.isSymbolicLink ?? false
        var signals = ["browser-cache"]
        signals.append(kind.rawValue)
        if isSymbolicLink {
            signals.append("symlink-not-followed")
        }
        return BrowserCacheItem(
            path: url.path,
            displayName: url.lastPathComponent,
            browser: browser,
            kind: kind,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            itemCount: measurement.itemCount,
            isDirectory: values?.isDirectory ?? false,
            isSymbolicLink: isSymbolicLink,
            modificationDate: values?.contentModificationDate,
            signals: signals,
            recommendation: "Quit \(browser.label), verify no active browser work needs this cache, then use a dry-run cleanup plan or browser UI before removal.",
            guidance: [
                "Cache is usually rebuildable, but browser profiles, bookmarks, cookies, history, passwords, and extensions are not part of this cache review.",
                "Quit the browser and verify open handles before cleanup."
            ] + (isSymbolicLink ? ["Symbolic link was not followed while measuring."] : [])
        )
    }

    private func protectedProfileRoot(for url: URL) -> BrowserCacheProtectedProfileRoot {
        let url = url.standardizedFileURL
        let browser = Self.browser(for: url)
        var isDirectory: ObjCBool = false
        let state: PermissionState
        let note: String
        if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            state = .missing
            note = "Profile root is not present at this path."
        } else if !isDirectory.boolValue {
            state = .unknown
            note = "Profile root path exists but is not a directory; Ryddi does not treat it as cache."
        } else if !fileManager.isReadableFile(atPath: url.path) {
            state = .denied
            note = "Profile root exists but is not readable; it remains protected from cache review."
        } else {
            state = .readable
            note = "Profile root may contain bookmarks, cookies, history, passwords, extensions, sessions, and sync state; it is intentionally not measured as cache."
        }
        return BrowserCacheProtectedProfileRoot(browser: browser, path: url.path, permissionState: state, note: note)
    }

    private func measure(url: URL, maxDepth: Int) -> BrowserCacheMeasurement {
        guard let values = try? url.resourceValues(forKeys: Set(browserCacheResourceKeys)) else {
            return BrowserCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)
        }
        if values.isSymbolicLink == true {
            return BrowserCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return BrowserCacheMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1)
        }
        guard maxDepth > 0 else {
            return BrowserCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: browserCacheResourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return BrowserCacheMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 1)
        }
        for case let child as URL in enumerator {
            let depth = max(0, child.pathComponents.count - url.pathComponents.count)
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(browserCacheResourceKeys)) else { continue }
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
        return BrowserCacheMeasurement(logicalSize: logical, allocatedSize: allocated, itemCount: count)
    }

    private static func browserSummaries(for items: [BrowserCacheItem]) -> [BrowserCacheSummary] {
        BrowserCacheBrowser.allCases.compactMap { browser in
            let matches = items.filter { $0.browser == browser }
            guard !matches.isEmpty else { return nil }
            return BrowserCacheSummary(
                name: browser.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func kindSummaries(for items: [BrowserCacheItem]) -> [BrowserCacheSummary] {
        BrowserCacheKind.allCases.compactMap { kind in
            let matches = items.filter { $0.kind == kind }
            guard !matches.isEmpty else { return nil }
            return BrowserCacheSummary(
                name: kind.label,
                itemCount: matches.count,
                allocatedSize: matches.reduce(Int64(0)) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func browser(for url: URL) -> BrowserCacheBrowser {
        let lower = url.path.lowercased()
        if lower.contains("google/chrome") || lower.contains("com.google.chrome") { return .chrome }
        if lower.contains("firefox") || lower.contains("mozilla") { return .firefox }
        if lower.contains("safari") { return .safari }
        if lower.contains("webkit") { return .webKit }
        if lower.contains("microsoft edge") || lower.contains("edgemac") { return .edge }
        if lower.contains("bravesoftware") || lower.contains("brave-browser") { return .brave }
        if lower.contains("arc") || lower.contains("company.thebrowser") { return .arc }
        return .other
    }

    private static func kind(for url: URL) -> BrowserCacheKind {
        let lower = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()
        if lower.contains("code cache") || path.contains("/code cache/") { return .codeCache }
        if lower.contains("gpucache") || lower.contains("gpu cache") { return .gpuCache }
        if lower.contains("media cache") || lower.contains("mediacache") { return .mediaCache }
        if lower.contains("service worker") || lower.contains("serviceworker") { return .serviceWorkerCache }
        if lower.contains("network") { return .networkCache }
        if lower.contains("cache") || lower.contains("cache_data") { return .diskCache }
        return .otherCache
    }

    public static let guidance = [
        "Quit browsers before planning browser-cache cleanup.",
        "Treat browser profiles, cookies, bookmarks, history, passwords, extensions, sessions, and sync state as protected app state.",
        "Prefer browser settings or a Ryddi dry-run plan for cache cleanup; do not raw-delete unknown profile folders."
    ]

    public static let nonClaims = [
        "Browser Cache Review is report-only; it does not delete, move, Trash, reset, or modify browser files.",
        "Ryddi does not measure browser profile roots as cache because they can contain bookmarks, cookies, passwords, extensions, sessions, history, and sync state.",
        "Cache classification is path-based and cannot prove a browser is fully quit or that all active handles are closed.",
        "Browser cache size is not promised immediate free-space recovery because APFS snapshots, purgeable storage, and concurrent browser activity can affect accounting."
    ]
}

private struct BrowserCacheMeasurement: Hashable {
    let logicalSize: Int64
    let allocatedSize: Int64
    let itemCount: Int
}

private let browserCacheResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]
