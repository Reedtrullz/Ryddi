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

public enum BrowserCacheRuntimeState: String, Codable, Hashable, Sendable {
    case running
    case notRunning
    case unknown

    public var label: String {
        switch self {
        case .running: return "Running"
        case .notRunning: return "Not running"
        case .unknown: return "Unknown"
        }
    }
}

public struct BrowserProcessSnapshot: Hashable, Sendable {
    public let processNames: [String]
    public let isAvailable: Bool
    public let errorMessage: String?

    public init(processNames: [String], isAvailable: Bool = true, errorMessage: String? = nil) {
        self.processNames = processNames
        self.isAvailable = isAvailable
        self.errorMessage = errorMessage
    }

    public static func current() -> BrowserProcessSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return BrowserProcessSnapshot(
                processNames: [],
                isAvailable: false,
                errorMessage: "Could not inspect process list: \(error.localizedDescription)"
            )
        }

        guard process.terminationStatus == 0 else {
            return BrowserProcessSnapshot(
                processNames: [],
                isAvailable: false,
                errorMessage: "Process list command exited with status \(process.terminationStatus)."
            )
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let names = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }

        return BrowserProcessSnapshot(processNames: names)
    }
}

public struct BrowserCacheRuntimeSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { browser.rawValue }
    public let browser: BrowserCacheBrowser
    public let state: BrowserCacheRuntimeState
    public let matchedProcessNames: [String]
    public let note: String
    public let guidance: [String]

    public init(
        browser: BrowserCacheBrowser,
        state: BrowserCacheRuntimeState,
        matchedProcessNames: [String],
        note: String,
        guidance: [String]
    ) {
        self.browser = browser
        self.state = state
        self.matchedProcessNames = matchedProcessNames
        self.note = note
        self.guidance = guidance
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
    public let runtimeSummaries: [BrowserCacheRuntimeSummary]
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
        runtimeSummaries: [BrowserCacheRuntimeSummary],
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
        self.runtimeSummaries = runtimeSummaries
        self.guidance = guidance
        self.nonClaims = nonClaims
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case totalLogicalSize
        case totalAllocatedSize
        case itemCount
        case displayedItemCount
        case candidateBytes
        case rootSummaries
        case browserSummaries
        case kindSummaries
        case largestItems
        case protectedProfileRoots
        case runtimeSummaries
        case guidance
        case nonClaims
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            totalLogicalSize: try container.decode(Int64.self, forKey: .totalLogicalSize),
            totalAllocatedSize: try container.decode(Int64.self, forKey: .totalAllocatedSize),
            itemCount: try container.decode(Int.self, forKey: .itemCount),
            displayedItemCount: try container.decode(Int.self, forKey: .displayedItemCount),
            candidateBytes: try container.decode(Int64.self, forKey: .candidateBytes),
            rootSummaries: try container.decodeIfPresent([BrowserCacheRootSummary].self, forKey: .rootSummaries) ?? [],
            browserSummaries: try container.decodeIfPresent([BrowserCacheSummary].self, forKey: .browserSummaries) ?? [],
            kindSummaries: try container.decodeIfPresent([BrowserCacheSummary].self, forKey: .kindSummaries) ?? [],
            largestItems: try container.decodeIfPresent([BrowserCacheItem].self, forKey: .largestItems) ?? [],
            protectedProfileRoots: try container.decodeIfPresent([BrowserCacheProtectedProfileRoot].self, forKey: .protectedProfileRoots) ?? [],
            runtimeSummaries: try container.decodeIfPresent([BrowserCacheRuntimeSummary].self, forKey: .runtimeSummaries) ?? [],
            guidance: try container.decodeIfPresent([String].self, forKey: .guidance) ?? [],
            nonClaims: try container.decodeIfPresent([String].self, forKey: .nonClaims) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(totalLogicalSize, forKey: .totalLogicalSize)
        try container.encode(totalAllocatedSize, forKey: .totalAllocatedSize)
        try container.encode(itemCount, forKey: .itemCount)
        try container.encode(displayedItemCount, forKey: .displayedItemCount)
        try container.encode(candidateBytes, forKey: .candidateBytes)
        try container.encode(rootSummaries, forKey: .rootSummaries)
        try container.encode(browserSummaries, forKey: .browserSummaries)
        try container.encode(kindSummaries, forKey: .kindSummaries)
        try container.encode(largestItems, forKey: .largestItems)
        try container.encode(protectedProfileRoots, forKey: .protectedProfileRoots)
        try container.encode(runtimeSummaries, forKey: .runtimeSummaries)
        try container.encode(guidance, forKey: .guidance)
        try container.encode(nonClaims, forKey: .nonClaims)
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
    private let processSnapshotProvider: @Sendable () -> BrowserProcessSnapshot

    public init(
        fileManager: FileManager = .default,
        processSnapshotProvider: @escaping @Sendable () -> BrowserProcessSnapshot = BrowserProcessSnapshot.current
    ) {
        self.fileManager = fileManager
        self.processSnapshotProvider = processSnapshotProvider
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
        let runtimeBrowsers = Self.runtimeBrowsers(
            rootSummaries: summaries,
            items: sortedItems,
            protectedProfileRoots: protectedProfiles
        )
        let runtimeSummaries = Self.runtimeSummaries(
            for: runtimeBrowsers,
            snapshot: processSnapshotProvider()
        )

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
            runtimeSummaries: runtimeSummaries,
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

    private static func runtimeBrowsers(
        rootSummaries: [BrowserCacheRootSummary],
        items: [BrowserCacheItem],
        protectedProfileRoots: [BrowserCacheProtectedProfileRoot]
    ) -> [BrowserCacheBrowser] {
        var browsers = Set<BrowserCacheBrowser>()
        for item in items where item.browser != .other {
            browsers.insert(item.browser)
        }
        for root in rootSummaries where root.permissionState != .missing && root.browser != .other {
            browsers.insert(root.browser)
        }
        for profile in protectedProfileRoots where profile.permissionState != .missing && profile.browser != .other {
            browsers.insert(profile.browser)
        }
        return BrowserCacheBrowser.allCases.filter { browsers.contains($0) }
    }

    private static func runtimeSummaries(
        for browsers: [BrowserCacheBrowser],
        snapshot: BrowserProcessSnapshot
    ) -> [BrowserCacheRuntimeSummary] {
        browsers.map { browser in
            guard snapshot.isAvailable else {
                return BrowserCacheRuntimeSummary(
                    browser: browser,
                    state: .unknown,
                    matchedProcessNames: [],
                    note: snapshot.errorMessage ?? "Ryddi could not inspect the local process list.",
                    guidance: [
                        "Treat \(browser.label) runtime state as unknown before cleanup.",
                        "Quit \(browser.label) manually and use Active Handles Review or a dry run before any cache cleanup."
                    ]
                )
            }

            let matches = matchingProcessNames(for: browser, in: snapshot.processNames)
            if matches.isEmpty {
                return BrowserCacheRuntimeSummary(
                    browser: browser,
                    state: .notRunning,
                    matchedProcessNames: [],
                    note: "No matching \(browser.label) process was observed in the local process list.",
                    guidance: [
                        "No matching process was observed, but cache cleanup should still use a dry run and open-handle checks.",
                        "Browser helper processes can start or stop while a report is being created."
                    ]
                )
            }

            return BrowserCacheRuntimeSummary(
                browser: browser,
                state: .running,
                matchedProcessNames: matches,
                note: "Matching \(browser.label) process observed: \(matches.prefix(4).joined(separator: ", ")).",
                guidance: [
                    "Quit \(browser.label) before cleanup and rerun Browser Cache Review or Active Handles Review.",
                    "Open windows, downloads, sessions, and signed-in browser state can still be active even when cache folders look reclaimable."
                ]
            )
        }
    }

    private static func matchingProcessNames(for browser: BrowserCacheBrowser, in processNames: [String]) -> [String] {
        let needles = processNameNeedles(for: browser)
        var seen = Set<String>()
        var matches: [String] = []
        for name in processNames {
            let lower = name.lowercased()
            guard needles.contains(where: { lower == $0 || lower.contains($0) }) else { continue }
            guard seen.insert(name).inserted else { continue }
            matches.append(name)
            if matches.count >= 12 { break }
        }
        return matches
    }

    private static func processNameNeedles(for browser: BrowserCacheBrowser) -> [String] {
        switch browser {
        case .chrome:
            return ["google chrome", "chrome", "chromium"]
        case .firefox:
            return ["firefox", "plugin-container"]
        case .safari:
            return ["safari"]
        case .edge:
            return ["microsoft edge", "edgemac"]
        case .brave:
            return ["brave browser", "brave-browser", "brave"]
        case .arc:
            return ["arc", "company.thebrowser.browser"]
        case .webKit:
            return ["webkit", "web content", "networking"]
        case .other:
            return []
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
        "Runtime status is based on local process-name matching and should be treated as advisory evidence.",
        "Treat browser profiles, cookies, bookmarks, history, passwords, extensions, sessions, and sync state as protected app state.",
        "Prefer browser settings or a Ryddi dry-run plan for cache cleanup; do not raw-delete unknown profile folders."
    ]

    public static let nonClaims = [
        "Browser Cache Review is report-only; it does not delete, move, Trash, reset, or modify browser files.",
        "Ryddi does not measure browser profile roots as cache because they can contain bookmarks, cookies, passwords, extensions, sessions, history, and sync state.",
        "Cache classification is path-based and cannot prove a browser is fully quit or that all active handles are closed.",
        "Browser process detection is advisory and can miss helper processes, stale process names, sandboxed helpers, or processes that start after the report.",
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
