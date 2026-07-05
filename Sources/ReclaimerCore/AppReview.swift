import Foundation

public struct AppReviewOptions: Codable, Hashable, Sendable {
    public let appRoots: [URL]
    public let home: URL
    public let includeSystemApplications: Bool
    public let includeOrphanCandidates: Bool
    public let minimumRelatedSize: Int64
    public let maximumAppSearchDepth: Int
    public let measurementDepth: Int

    public init(
        appRoots: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeSystemApplications: Bool = false,
        includeOrphanCandidates: Bool = true,
        minimumRelatedSize: Int64 = 1_000_000,
        maximumAppSearchDepth: Int = 4,
        measurementDepth: Int = 4
    ) {
        let defaultRoots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]
        var roots = appRoots ?? defaultRoots
        if includeSystemApplications {
            roots.append(URL(fileURLWithPath: "/System/Applications"))
        }
        self.appRoots = roots.map(\.standardizedFileURL)
        self.home = home.standardizedFileURL
        self.includeSystemApplications = includeSystemApplications
        self.includeOrphanCandidates = includeOrphanCandidates
        self.minimumRelatedSize = minimumRelatedSize
        self.maximumAppSearchDepth = maximumAppSearchDepth
        self.measurementDepth = measurementDepth
    }
}

public struct InstalledApp: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let executableName: String?
    public let path: String
    public let modificationDate: Date?

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String?,
        version: String?,
        executableName: String?,
        path: String,
        modificationDate: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.executableName = executableName
        self.path = path
        self.modificationDate = modificationDate
    }
}

public struct AppReviewItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let ownerKey: String
    public let path: String
    public let displayName: String
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let isDirectory: Bool
    public let modificationDate: Date?
    public let category: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let evidence: [Evidence]

    public init(
        id: String = UUID().uuidString,
        ownerKey: String,
        path: String,
        displayName: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        isDirectory: Bool,
        modificationDate: Date?,
        category: String,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        evidence: [Evidence]
    ) {
        self.id = id
        self.ownerKey = ownerKey
        self.path = path
        self.displayName = displayName
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
        self.category = category
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.evidence = evidence
    }
}

public struct AppReviewGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let ownerName: String
    public let bundleIdentifier: String?
    public let appPath: String?
    public let isInstalled: Bool
    public let items: [AppReviewItem]
    public let totalAllocatedSize: Int64
    public let highestRiskClass: SafetyClass
    public let notes: [String]

    public init(
        id: String,
        ownerName: String,
        bundleIdentifier: String?,
        appPath: String?,
        isInstalled: Bool,
        items: [AppReviewItem],
        notes: [String]
    ) {
        self.id = id
        self.ownerName = ownerName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.isInstalled = isInstalled
        self.items = items.sorted { lhs, rhs in
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.path < rhs.path
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        self.totalAllocatedSize = items.reduce(0) { $0 + $1.allocatedSize }
        self.highestRiskClass = items.max { $0.safetyClass.riskRank < $1.safetyClass.riskRank }?.safetyClass ?? .reviewRequired
        self.notes = notes
    }
}

public struct AppReviewReport: Codable, Hashable, Sendable {
    public let createdAt: Date
    public let appRoots: [String]
    public let installedApps: [InstalledApp]
    public let installedAppGroups: [AppReviewGroup]
    public let orphanGroups: [AppReviewGroup]
    public let skipped: [String]
    public let notes: [String]

    public init(
        createdAt: Date = Date(),
        appRoots: [String],
        installedApps: [InstalledApp],
        installedAppGroups: [AppReviewGroup],
        orphanGroups: [AppReviewGroup],
        skipped: [String],
        notes: [String]
    ) {
        self.createdAt = createdAt
        self.appRoots = appRoots
        self.installedApps = installedApps
        self.installedAppGroups = installedAppGroups
        self.orphanGroups = orphanGroups
        self.skipped = skipped
        self.notes = notes
    }

    public var relatedItemCount: Int {
        installedAppGroups.reduce(0) { $0 + $1.items.count } + orphanGroups.reduce(0) { $0 + $1.items.count }
    }

    public var reviewBytes: Int64 {
        installedAppGroups.reduce(0) { $0 + $1.totalAllocatedSize } + orphanGroups.reduce(0) { $0 + $1.totalAllocatedSize }
    }
}

public final class AppReviewScanner: @unchecked Sendable {
    private struct Measurement {
        let logicalSize: Int64
        let allocatedSize: Int64
        let itemCount: Int
        let isDirectory: Bool
        let modificationDate: Date?
    }

    private let fileManager: FileManager
    private let ruleEngine: RuleEngine

    public init(fileManager: FileManager = .default, ruleEngine: RuleEngine? = nil) throws {
        self.fileManager = fileManager
        self.ruleEngine = try ruleEngine ?? RuleEngine.bundled()
    }

    public func scan(options: AppReviewOptions = AppReviewOptions()) -> AppReviewReport {
        var skipped: [String] = []
        let apps = discoverApps(options: options, skipped: &skipped)
        let knownKeys = Set(apps.flatMap(searchKeys(for:)))
        let installedGroups = installedRelatedGroups(apps: apps, options: options, skipped: &skipped)
        let orphanGroups = options.includeOrphanCandidates
            ? orphanedGroups(knownKeys: knownKeys, options: options, skipped: &skipped)
            : []

        return AppReviewReport(
            appRoots: options.appRoots.map(\.path),
            installedApps: apps,
            installedAppGroups: installedGroups,
            orphanGroups: orphanGroups,
            skipped: skipped,
            notes: [
                "Apps & Leftovers is review-only. Ryddi does not uninstall apps or delete related files from this report.",
                "Installed-app support data can include preferences, licenses, projects, plugins, and state; review before removal.",
                "Orphan candidates are heuristic app-owned-looking files with no currently discovered app match, not proof that the app is gone.",
                "Use vendor uninstallers or explicit manual Trash moves for app removal; keep GarageBand/Logic and creative assets protected."
            ]
        )
    }

    private func discoverApps(options: AppReviewOptions, skipped: inout [String]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seenPaths = Set<String>()

        for root in options.appRoots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                appendAppSkip("Missing app root: \(root.path)", to: &skipped)
                continue
            }
            guard isDirectory.boolValue, fileManager.isReadableFile(atPath: root.path) else {
                appendAppSkip("Unreadable app root: \(root.path)", to: &skipped)
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: appResourceKeys,
                options: [.skipsPackageDescendants, .skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                appendAppSkip("Could not enumerate app root: \(root.path)", to: &skipped)
                continue
            }

            let rootDepth = root.pathComponents.count
            for case let url as URL in enumerator {
                let depth = max(0, url.standardizedFileURL.pathComponents.count - rootDepth)
                if depth > options.maximumAppSearchDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard seenPaths.insert(url.standardizedFileURL.path).inserted else { continue }
                guard let app = appInfo(at: url) else {
                    appendAppSkip("Could not read app metadata: \(url.path)", to: &skipped)
                    continue
                }
                apps.append(app)
            }
        }

        return apps.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func appInfo(at url: URL) -> InstalledApp? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: infoURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any] }
        let values = try? url.resourceValues(forKeys: Set(appResourceKeys))
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        let displayName = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(
            id: bundleIdentifier ?? url.standardizedFileURL.path,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            version: info?["CFBundleShortVersionString"] as? String,
            executableName: info?["CFBundleExecutable"] as? String,
            path: url.standardizedFileURL.path,
            modificationDate: values?.contentModificationDate
        )
    }

    private func installedRelatedGroups(apps: [InstalledApp], options: AppReviewOptions, skipped: inout [String]) -> [AppReviewGroup] {
        apps.compactMap { app in
            var seen = Set<String>()
            let items = relatedURLs(for: app, home: options.home)
                .filter { seen.insert($0.standardizedFileURL.path).inserted }
                .compactMap { url in
                    makeItem(
                        ownerKey: app.bundleIdentifier ?? normalizeOwnerKey(app.displayName),
                        url: url,
                        minimumSize: options.minimumRelatedSize,
                        measurementDepth: options.measurementDepth,
                        installedAppContext: true,
                        skipped: &skipped
                    )
                }
            guard !items.isEmpty else { return nil }
            return AppReviewGroup(
                id: app.id,
                ownerName: app.displayName,
                bundleIdentifier: app.bundleIdentifier,
                appPath: app.path,
                isInstalled: true,
                items: items,
                notes: [
                    "Related files for an installed app are not leftovers. They may be useful state or preferences.",
                    "Caches and logs may be removable after quitting the app, but this report does not select cleanup actions."
                ]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalAllocatedSize == rhs.totalAllocatedSize {
                return lhs.ownerName < rhs.ownerName
            }
            return lhs.totalAllocatedSize > rhs.totalAllocatedSize
        }
    }

    private func orphanedGroups(knownKeys: Set<String>, options: AppReviewOptions, skipped: inout [String]) -> [AppReviewGroup] {
        var buckets: [String: [AppReviewItem]] = [:]
        for root in orphanRoots(home: options.home) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root.url,
                includingPropertiesForKeys: appResourceKeys,
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else {
                if fileManager.fileExists(atPath: root.url.path) {
                    appendAppSkip("Could not list app-support root: \(root.url.path)", to: &skipped)
                }
                continue
            }

            for child in children {
                guard let ownerKey = ownerKey(for: child, rootKind: root.kind) else { continue }
                guard !knownKeys.contains(ownerKey), !isProtectedOwnerKey(ownerKey) else { continue }
                guard let item = makeItem(
                    ownerKey: ownerKey,
                    url: child,
                    minimumSize: options.minimumRelatedSize,
                    measurementDepth: options.measurementDepth,
                    installedAppContext: false,
                    skipped: &skipped
                ) else { continue }
                buckets[ownerKey, default: []].append(item)
            }
        }

        return buckets.map { ownerKey, items in
            AppReviewGroup(
                id: "orphan:\(ownerKey)",
                ownerName: ownerKey,
                bundleIdentifier: ownerKey.contains(".") ? ownerKey : nil,
                appPath: nil,
                isInstalled: false,
                items: items,
                notes: [
                    "No installed app with this identifier/name was found in the configured app roots.",
                    "This is a heuristic leftover candidate; verify the owning app is truly removed before moving anything to Trash."
                ]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalAllocatedSize == rhs.totalAllocatedSize {
                return lhs.ownerName < rhs.ownerName
            }
            return lhs.totalAllocatedSize > rhs.totalAllocatedSize
        }
    }

    private func makeItem(
        ownerKey: String,
        url: URL,
        minimumSize: Int64,
        measurementDepth: Int,
        installedAppContext: Bool,
        skipped: inout [String]
    ) -> AppReviewItem? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: Set(appResourceKeys))
        guard values?.isSymbolicLink != true else { return nil }
        let measurement = measure(url: url, maxDepth: measurementDepth)
        guard measurement.allocatedSize >= minimumSize else { return nil }

        let classification = ruleEngine.classify(
            path: url.path,
            isDirectory: measurement.isDirectory,
            isSymbolicLink: values?.isSymbolicLink == true
        )
        guard classification.safetyClass != .neverTouch else {
            appendAppSkip("Skipped never-touch app-related path: \(url.path)", to: &skipped)
            return nil
        }

        let policy = appReviewPolicy(for: url.path, classification: classification, installedAppContext: installedAppContext)
        return AppReviewItem(
            ownerKey: ownerKey,
            path: url.standardizedFileURL.path,
            displayName: url.lastPathComponent,
            logicalSize: measurement.logicalSize,
            allocatedSize: measurement.allocatedSize,
            isDirectory: measurement.isDirectory,
            modificationDate: measurement.modificationDate,
            category: policy.category,
            safetyClass: policy.safetyClass,
            actionKind: policy.actionKind,
            evidence: policy.evidence + [
                Evidence(kind: "app-review.size", message: "Allocated size: \(ByteFormat.string(measurement.allocatedSize)); logical size: \(ByteFormat.string(measurement.logicalSize))."),
                Evidence(kind: "app-review.scope", message: installedAppContext ? "Matched a currently installed app." : "No installed app match found in configured app roots.")
            ]
        )
    }

    private func relatedURLs(for app: InstalledApp, home: URL) -> [URL] {
        let library = home.appendingPathComponent("Library")
        let keys = searchKeys(for: app)
        var urls: [URL] = []
        for key in keys {
            urls.append(library.appendingPathComponent("Application Support").appendingPathComponent(key))
            urls.append(library.appendingPathComponent("Caches").appendingPathComponent(key))
            urls.append(library.appendingPathComponent("Logs").appendingPathComponent(key))
            urls.append(library.appendingPathComponent("Containers").appendingPathComponent(key))
            urls.append(library.appendingPathComponent("HTTPStorages").appendingPathComponent(key))
            urls.append(library.appendingPathComponent("WebKit").appendingPathComponent(key))
        }
        if let bundleIdentifier = app.bundleIdentifier {
            urls.append(library.appendingPathComponent("Preferences").appendingPathComponent("\(bundleIdentifier).plist"))
            urls.append(library.appendingPathComponent("Saved Application State").appendingPathComponent("\(bundleIdentifier).savedState"))
            urls.append(library.appendingPathComponent("Cookies").appendingPathComponent("\(bundleIdentifier).binarycookies"))
            urls.append(library.appendingPathComponent("LaunchAgents").appendingPathComponent("\(bundleIdentifier).plist"))
        }
        return urls
    }

    private func measure(url: URL, maxDepth: Int) -> Measurement {
        guard let values = try? url.resourceValues(forKeys: Set(appResourceKeys)) else {
            return Measurement(logicalSize: 0, allocatedSize: 0, itemCount: 0, isDirectory: false, modificationDate: nil)
        }
        if values.isSymbolicLink == true {
            return Measurement(logicalSize: 0, allocatedSize: 0, itemCount: 1, isDirectory: false, modificationDate: values.contentModificationDate)
        }
        if values.isDirectory != true {
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return Measurement(logicalSize: logical, allocatedSize: allocated, itemCount: 1, isDirectory: false, modificationDate: values.contentModificationDate)
        }
        guard maxDepth > 0 else {
            return Measurement(logicalSize: 0, allocatedSize: 0, itemCount: 1, isDirectory: true, modificationDate: values.contentModificationDate)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 1
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: appResourceKeys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return Measurement(logicalSize: 0, allocatedSize: 0, itemCount: 1, isDirectory: true, modificationDate: values.contentModificationDate)
        }

        for case let child as URL in enumerator {
            count += 1
            guard let childValues = try? child.resourceValues(forKeys: Set(appResourceKeys)) else { continue }
            if childValues.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if childValues.isDirectory == true { continue }
            logical += Int64(childValues.fileSize ?? 0)
            allocated += Int64(childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return Measurement(logicalSize: logical, allocatedSize: allocated, itemCount: count, isDirectory: true, modificationDate: values.contentModificationDate)
    }
}

private struct OrphanRoot {
    let url: URL
    let kind: String
}

private let appResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isRegularFileKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey
]

private func searchKeys(for app: InstalledApp) -> [String] {
    var keys: [String] = []
    if let bundleIdentifier = app.bundleIdentifier {
        keys.append(bundleIdentifier)
    }
    keys.append(app.displayName)
    if let executableName = app.executableName {
        keys.append(executableName)
    }
    return Array(Set(keys.map(normalizeOwnerKey).filter { !$0.isEmpty }))
}

private func normalizeOwnerKey(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func orphanRoots(home: URL) -> [OrphanRoot] {
    let library = home.appendingPathComponent("Library")
    return [
        OrphanRoot(url: library.appendingPathComponent("Application Support"), kind: "support"),
        OrphanRoot(url: library.appendingPathComponent("Caches"), kind: "cache"),
        OrphanRoot(url: library.appendingPathComponent("Logs"), kind: "logs"),
        OrphanRoot(url: library.appendingPathComponent("Preferences"), kind: "preferences"),
        OrphanRoot(url: library.appendingPathComponent("Saved Application State"), kind: "savedState"),
        OrphanRoot(url: library.appendingPathComponent("Containers"), kind: "containers"),
        OrphanRoot(url: library.appendingPathComponent("LaunchAgents"), kind: "launchAgents")
    ]
}

private func ownerKey(for url: URL, rootKind: String) -> String? {
    let name = url.lastPathComponent
    let lower = name.lowercased()
    switch rootKind {
    case "preferences", "launchAgents":
        guard lower.hasSuffix(".plist") else { return nil }
        return normalizeOwnerKey(String(name.dropLast(".plist".count)))
    case "savedState":
        guard lower.hasSuffix(".savedstate") else { return nil }
        return normalizeOwnerKey(String(name.dropLast(".savedState".count)))
    default:
        return normalizeOwnerKey(name)
    }
}

private func isProtectedOwnerKey(_ key: String) -> Bool {
    let lower = key.lowercased()
    if lower.hasPrefix("com.apple.") || lower == "apple" { return true }
    if lower.contains("garageband") || lower.contains("logic") { return true }
    if lower.contains("photos") || lower.contains("music") { return true }
    if lower.contains("keychain") || lower.contains("login") { return true }
    return false
}

private func appReviewPolicy(
    for path: String,
    classification: Classification,
    installedAppContext: Bool
) -> (category: String, safetyClass: SafetyClass, actionKind: ActionKind, evidence: [Evidence]) {
    let lower = path.lowercased()
    if classification.safetyClass == .preserveByDefault || classification.safetyClass == .neverTouch {
        return (
            classification.matches.first?.category ?? "App support",
            classification.safetyClass,
            .reportOnly,
            classification.evidence
        )
    }
    if lower.contains("/library/caches/") {
        return (
            "App cache",
            installedAppContext ? .safeAfterCondition : .reviewRequired,
            .openGuidance,
            [Evidence(kind: "app-review.cache", message: installedAppContext ? "Cache belongs to an installed app; quit the app and review before cleanup." : "Cache has no discovered installed app owner; review as a possible leftover.")]
        )
    }
    if lower.contains("/library/logs/") {
        return (
            "App logs",
            .reviewRequired,
            .openGuidance,
            [Evidence(kind: "app-review.logs", message: "Logs are diagnostic history; review recency and troubleshooting value before removal.")]
        )
    }
    if lower.contains("/library/preferences/") {
        return (
            "App preferences",
            .preserveByDefault,
            .reportOnly,
            [Evidence(kind: "app-review.preferences", message: "Preferences can contain license, account, or user configuration state.")]
        )
    }
    if lower.contains("/library/containers/") || lower.contains("/library/application support/") {
        return (
            "App state",
            .preserveByDefault,
            .reportOnly,
            [Evidence(kind: "app-review.state", message: "App support and container data can include user data, plugins, databases, or project state.")]
        )
    }
    if lower.contains("/library/launchagents/") {
        return (
            "Launch agent",
            .reviewRequired,
            .openGuidance,
            [Evidence(kind: "app-review.launch-agent", message: "Launch agents can start background processes; inspect before removal.")]
        )
    }
    return (
        classification.matches.first?.category ?? "App support",
        .reviewRequired,
        .openGuidance,
        classification.evidence
    )
}

private func appendAppSkip(_ message: String, to skipped: inout [String]) {
    guard skipped.count < 200, skipped.last != message else { return }
    skipped.append(message)
}
